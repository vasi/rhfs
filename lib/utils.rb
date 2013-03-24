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
	
	def self.open(path, rw = false, &block)
		type = file = nil
		[Sparsebundle, IOBuffer].each do |k|
			begin
				type, file = k, k.new(path)
				break
			rescue MagicException
			end
		end
		raise "Unknown file '#{path}'" unless file
		
		block.(type, file)
	ensure
		file.close if file
	end
	
	def self.sparsebundle_open_or_create(path, size, band_spec, &block)
		sb = nil
		band_size = size_spec(band_spec || Sparsebundle::DefaultBandSizeOpt)
		begin
			sb = Sparsebundle.new(path)
			raise "Existing sparsebundle has different band size" \
				if size_spec && band_size != sb.band_size
		rescue MagicException
			sb = Sparsebundle.create(path, size, band_size)
		end
		block.(sb)
	ensure
		sb.close if sb
	end
end
