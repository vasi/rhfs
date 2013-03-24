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
	
	def self.buf_open(path, rw = true, &block)
		type = file = nil
		unless File.exist?(path)
			block.(nil, nil)
			return
		end
		
		[Sparsebundle, IOBuffer].each do |k|
			begin
				type, file = k, k.new(path, rw)
				break
			rescue MagicException
			end
		end
		raise "Unknown file '#{path}'" unless file
		
		block.(type, file)
	ensure
		file.close if file
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
end
