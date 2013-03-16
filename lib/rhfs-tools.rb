require 'tmpdir'

require_relative 'apm'
require_relative 'hfs'
require_relative 'hdiutil'
require_relative 'sparsebundle'

class RHFS
	TypeUnwrapped = 'RHFS_Unwrap'
	
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
		)
		hfs.set_flags(*%w[Valid Allocated Readable Writable])
		
		apm.partitions = [pmap, hfs]
		apm.write
		sb.close
	end
	
	def self.create_hdiutil(path, partitioned, size, band_size)
		band_sectors = band_size / Sparsebundle::Sector
		args = %w{-plist -type SPARSEBUNDLE -fs HFS+}
		args << '-size' << size
		args << '-imagekey' << "sparse-band-size=#{band_sectors}"
		args.concat(%{-layout SPUD}) if partitioned
		Hdiutil.create(file, *args)
	end
	
	def self.unwrap(buf)
		# Make sure we have a valid disk
		apm = APM.new(buf)
		idxs = apm.partitions.each_with_index.
			select { |p,i| p.type == APM::TypeHFS }
		raise "Need exactly one HFS partition" unless idxs.count == 1
		
		idx = idxs[0][1]
		part = apm.partitions[idx]
		hfs = HFS.new(apm.partition(idx))
		raise "Not a wrapped HFS+ partition" \
			unless hfs.mdb.embedSigWord == HFS::MDB::EmbedSignature
		
		# Calculate the sizes of the new partitions
		bsize = apm.block0.blkSize
		pre_size_bytes = (hfs.mdb.alBlSt * HFS::Sector) +
			(hfs.mdb.embedStartBlock * hfs.mdb.alBlkSiz)		
		
		pre_size = pre_size_bytes / bsize
		wrap_size = hfs.mdb.embedBlockCount * hfs.mdb.alBlkSiz / bsize
		post_size = part.pblocks - pre_size - wrap_size
		sizes = [pre_size, wrap_size, post_size]
		
		# Build the new partitions
		start = part.pblock_start
		repl = sizes.each_with_index.map do |sz, i|
			pt = APM::Entry.new(part)
			pt.pblock_start = start
			pt.pblocks = sz
			pt.lblocks_start = pt.lblocks = 0
			if i % 2 == 0 # wrapper part
				pt.type = TypeUnwrapped
				pt.set_flags(*%w[Valid Allocated])
			end
			start += sz
			pt
		end
		apm.partitions[idx, 1] = repl
		apm.write
	end
	
	def self.rewrap(buf)
		# Make sure we have a valid disk
		apm = APM.new(buf)
		ws = apm.partitions.each_with_index.
			select { |p,i| p.type == TypeUnwrapped }
		raise "Need exactly two wrap partitions" unless ws.count == 2
		w1, wi1, w2, wi2 = *ws.flatten
		raise "Wrap partitions must surround a partition" unless wi2 - wi1 == 2
		h = apm.partitions[wi1 + 1]
		raise "There must be a HFS partition to unwrap" \
			unless h.type == APM::TypeHFS
		
		# Build the original partition
		r = APM::Entry.new(h)
		r.pblock_start = w1.pblock_start
		r.pblocks = w1.pblocks + h.pblocks + w2.pblocks
		apm.partitions[wi1, 3] = [r]
		apm.write
	end
	
	def self.compact(path)
		sb = Sparsebundle.new(path)
		apm = APM.new(sb)
		
		# Find a strategy
		hfs = apm.partitions.each_with_index.
			select { |p,i| p.type == APM::TypeHFS }.
			map { |p, i| { :part => p, :index => i,
				:type => HFS.identify(apm.partition(i)) } }
		plus = hfs.find { |p| p[:type] != :HFS }
		
		# HFS+ is present
		if plus
			raise "Can't compact multiple partitions with HFS+" \
				if hfs.count != 1
			wrapper = (plus[:type] == :HFSWrapper) 
			unwrap(sb) if wrapper
			sb.close
			Hdiutil.compact(path)
			if wrapper
				sb = Sparsebundle.new(path)
				rewrap(sb)
			end
		else
			# Only HFS
			raise "Can't yet compact plain HFS"
		end
	end
end

class RHFSCommands
	def self.create(opts, *args)
		# FIXME: test different args
		raise Trollop::CommandlineError.new("Bad number of arguments") \
			unless args.size == 2
		size, path = *args
		size = RHFS.size(size)
		band_size = RHFS.size(opts[:band])
		method = opts[:format] ? :create_hdiutil : :create_native
		RHFS.send(method, path, !opts[:whole], size, band_size)
	end
	
	def self.compact(opts, *args)
		raise Trollop::CommandlineError.new("Bad number of arguments") \
			unless args.size == 1
		path, = *args
		RHFS.compact(path)
	end
end
