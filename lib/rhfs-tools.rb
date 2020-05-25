require_relative 'apm'
require_relative 'compact'
require_relative 'hdiutil'
require_relative 'sparsebundle'
require_relative 'utils'

class RHFS
	def self.create_native(path, partitioned, size, band_size)
		Sparsebundle.create_approx(path, size, band_size) do |sb|
			return unless partitioned

			apm = APM.new(sb, APM::DONT_READ)
			apm.add(APM::TypeHFS, :flags => %w[Readable Writable])
			apm.write
		end
	end

	def self.create_hdiutil(path, partitioned, size, band_size)
		band_sectors = band_size / Sparsebundle::Sector
		args = %w{-plist -type SPARSEBUNDLE -fs HFS+}
		args << '-size' << size
		args << '-imagekey' << "sparse-band-size=#{band_sectors}"
		args << '-layout' << (partitioned ? 'SPUD' : 'NONE')
		Hdiutil.create(path, *args)
	end

	def self.compact_hdiutil(path)
		# hdiutil breaks unless we fixup HFS+ wrappers
		Sparsebundle.new(path) do |sb|
			compact_prep_vol(sb) # whole volume

			begin
				APM.new(sb).partitions { |pt| compact_prep_vol(pt.buffer) }
			rescue MagicException
			end
		end

		Hdiutil.compact(path)
	end

	def self.compact_native(path, search)
		Sparsebundle.new(path) do |sb|
			base = search ? ReadSizer.new(sb) : OpaqueSizer.new(sb.size)
			sizer = nil
			begin
				apm = APM.new(sb)
				sizer = apm.sizer
			rescue MagicException
				fs = APM.filesystem(sb)
				unless fs || search
					$stderr.puts "Can't easily compact this disk image"
					exit(-1)
				end
				sizer = fs.sizer if fs
			end

			sizer, base = base, nil unless sizer
			sb.compact(sizer, base)
		end
	end
end

class RHFSCommands
	def self.create(opts, *args)
		size, path, too_many = *args
		raise Optimist::CommandlineError.new("Bad number of arguments") \
			unless path && !too_many
		size = RHFS.size_spec(size)
		band_size = RHFS.size_spec(opts[:band])
		method = opts[:format] ? :create_hdiutil : :create_native
		RHFS.send(method, path, opts[:partition], size, band_size)
	end

	def self.compact(opts, *args)
		path, too_many = *args
		raise Optimist::CommandlineError.new("Bad number of arguments") \
			unless path && !too_many
		if opts[:apple]
			RHFS.compact_hdiutil(path)
		else
			RHFS.compact_native(path, opts[:search])
		end
	end

	def self.convert(opts, *args)
		input, output, too_many = *args
		raise Optimist::CommandlineError.new("Bad number of arguments") \
			unless output && !too_many

		formats = {:sparsebundle => Sparsebundle, :raw => IOBuffer}
		want = formats.keys.select { |k| opts[k] }.map { |k| formats[k] }
		raise Optimist::CommandlineError.new("Output can only be one format") \
			if want.count > 1
		format = want.first

		band_size = RHFS.size_spec(opts[:band] ||
			Sparsebundle::DefaultBandSizeOpt)

		RHFS.buf_open(input, false, :must_exist) do |itype, src|
			RHFS.buf_open(output) do |type, dst|
				raise "Existing output has wrong format" \
					if type && format && type != format
				raise "Existing sparsebundle has wrong band size" \
					if dst.respond_to?(:band_size) && opts[:band] &&
						dst.band_size != band_size

				# Default to opposite of input
				type ||= format ||
					(itype == Sparsebundle ? IOBuffer : Sparsebundle)
				raise Optimist::CommandlineError.new(
					"Band size only applies to sparsebundles") \
						if type != Sparsebundle && opts[:band]

				RHFS.buf_create(dst, type, output, src.size, band_size) do |d|
					src.copy(d)
				end
			end
		end
	end

	def self.access(opts, *args)
		img, path, too_many = *args
		raise Optimist::CommandlineError.new("Bad number of arguments") \
			unless path && !too_many

    opts[:fork] ||= 'data'
    case opts[:fork]
      when 'data'
        fork = HFSPlus::DataFork
      when 'resource'
        fork = HFSPlus::ResourceFork
      else
        raise Optimist::CommandlineError.new("Bad fork '#{opts[:fork]}'")
    end

    RHFS.hfs_read(img) do |hfs|
			fork = hfs.path_fork(path, fork) or raise "Path doesn't exist in image"
			output = opts[:output] ? open(opts[:output], 'w') : $stdout
			fork.copy(IOBuffer.new(output))
		end
	end

  def self.list(opts, *args)
		img, too_many = *args
		raise Optimist::CommandlineError.new("Bad number of arguments") \
			unless img && !too_many
    RHFS.hfs_read(img) do |hfs|
      hfs.catalog.tree_path do |leaf, path|
        puts path.join('/')
      end
    end
  end
end
