require 'tmpdir'

require_relative 'apm'
require_relative 'hfs'
require_relative 'hdiutil'
require_relative 'sparsebundle'

class RHFS
	# Allow suffixes for MB, g, etc
	def self.size(s)
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
	
	def self.create_native(path, partitioned, size, band_size)
		sb = Sparsebundle.create_approx(path, size, band_size)
		return unless partitioned
		
		apm = APM.create(sb)
		bsize = apm.block0.blkSize
		
		start = 1
		pmap = APM::Entry.new(
			:type => APM::TypePMAP,
			:pblock_start => start,
			:pblocks => APM::DefaultEntries,
		)
		
		start += APM::DefaultEntries
		hfs = APM::Entry.new(
			:type => APM::TypeHFS,
			:pblock_start => start,
			:pblocks => (size / bsize) - start,
			:flags => %w[Valid Allocated Readable Writable].
				reduce(0) { |a, f| a | APM::Entry.const_get(f) } 
		)
		
		apm.partitions = [pmap, hfs]
		apm.write
	end
	
	def self.create_hdiutil(path, partitioned, size, band_size)
		band_sectors = band_size / Sparsebundle::Sector
		args = %w{-plist -type SPARSEBUNDLE -fs HFS+}
		args << '-size' << size
		args << '-imagekey' << "sparse-band-size=#{band_sectors}"
		args.concat(%{-layout SPUD}) if partitioned
		Hdiutil.create(file, *args)
	end
end

class RHFSCommands
	def self.create(opts, *args)
		raise Trollop::CommandlineError.new("Bad number of arguments") \
			unless args.size == 2
		size, path = *args
		size = RHFS.size(size)
		band_size = RHFS.size(opts[:band])
		method = opts[:format] ? :create_hdiutil : :create_native
		RHFS.send(method, path, !opts[:whole], size, band_size)
	end
end
