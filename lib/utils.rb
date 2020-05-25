require_relative 'hfs'
require_relative 'hfsplus'

class RHFS
	# Allow suffixes for MB, g, etc
	def self.size_spec(s)
		suffixes = %w[k m g t]
		md = s.match(/^(\d+)(\D)?b?$/i) or raise "Unknown size #{s.inspect}"
		v = md[1].to_i
		if md[2]
			i = suffixes.find_index(md[2].downcase) \
				or raise "Unknown suffix #{md[2]}"
			v *= 1024 ** (i + 1)
		end
		return v
	end

	def self.compact_prep_vol(buf)
		return unless HFSPlus.identify(buf) == :HFSWrapper

		# Add the flag whose absence gives hdiutil trouble
		hfs = HFS.new(buf)
		hfs.mdb.atrb |= HFS::MDB::AtrbUnmounted
		hfs.write_mdb
	end

	def self.buf_open(path, rw = true, must_exist = false, opts = {}, &block)
		type = file = nil
		unless File.exist?(path)
			raise Optimist::CommandlineError.new(
				"Input file doesn't exist") if must_exist
			block.(nil, nil)
			return
		end

		[Sparsebundle, IOBuffer].each do |k|
			begin
        args = [path, rw]
        args << opts if k == Sparsebundle
				type, file = k, k.new(*args)
				break
			rescue MagicException
			end
		end
		raise "Unknown file '#{path}'" unless file

		block.(type, file)
	ensure
		file.close if file
	end

  def self.hfs_read(path, &block)
    buf_open(path, false, :must_exist, :lock => false) do |_, input|
      hfs = find_hfsplus(input)
      block.(hfs)
    end
  end

	def self.buf_create(obj, klass, path, size, band_size, &block)
		if obj
			block.(obj)
		elsif klass == Sparsebundle
			Sparsebundle.create(path, size, band_size, &block)
		else
			klass.new(path, :rw, &block)
		end
	end

	def self.find_hfsplus(buf)
		ok = proc do |b|
			i = HFSPlus.identify(b)
			i == :HFSPlus || i == :HFSX || i == :HFSWrapper
		end

		return HFSPlus.new(buf) if ok.(buf)
		apm = APM.new(buf)
		apm.partitions do |pt|
			b = pt.buffer
			return HFSPlus.new(b) if ok.(b)
		end
		raise "Can't find an HFS+ filesystem"
	end
end
