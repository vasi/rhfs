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
		raise Trollop::CommandlineError.new("Bad number of arguments") \
			unless path && !too_many
		size = RHFS.size_spec(size)
		band_size = RHFS.size_spec(opts[:band])
		method = opts[:format] ? :create_hdiutil : :create_native
		RHFS.send(method, path, opts[:partition], size, band_size)
	end
	
	def self.compact(opts, *args)
		path, too_many = *args
		raise Trollop::CommandlineError.new("Bad number of arguments") \
			unless path && !too_many
		if opts[:apple]
			RHFS.compact_hdiutil(path)
		else
			RHFS.compact_native(path, opts[:search])
		end
	end
	
	def self.convert(opts, *args)
		input, output, too_many = *args
		raise Trollop::CommandlineError.new("Bad number of arguments") \
			unless output && !too_many
		
		formats = [:sparsebundle, :raw].select { |k| opts[k] }
		raise Trollop::CommandlineError.new("Output can only be one format") \
			if formats.size > 1
		format, = *formats
		
		RHFS.open(input) do |type, src|
			format ||= (type == Sparsebundle ? :raw : :sparsebundle)
			raise Trollop::CommandlineError.new(
				"Band size only applies to sparsebundles") \
					if format != :sparsebundle && opts[:band]
			
			block = lambda { |dst| src.copy(dst) }
			case format
				when :raw; IOBuffer.new(output, &block)
				when :sparsebundle
					RHFS.sparsebundle_open_or_create(output, src.size,
						opts[:band], &block)
				else; raise "Unknown format"
			end
		end
	end
end
