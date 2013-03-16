require 'tmpdir'

require_relative 'apm'
require_relative 'hfs'
require_relative 'hdiutil'
require_relative 'sparsebundle'

class RHFS
	def self.seed_native(path, partitioned, size, band_size)
		sb = Sparsebundle.create(path, size, band_size)
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
end

class RHFSCommands
	# Corrupt an HFS partition, so MacOS offers to format it
	def self.seed(opts, file)
		if opts[:create]
			size = opts[:create]
			size += 'm' if size.match(/^\d+$/) # default to MB
			
			args = %w{-plist -type SPARSEBUNDLE -layout SPUD -fs HFS+}
			args << '-size' << size
			args.concat(opts[:extra_args].split) if opts[:extra_args]
			Hdiutil.create(file, *args)
			Hdiutil.attach(file) { |d| seed_device(d) }
		else
			seed_device(file)
		end
	end
	
	def self.seed_device(dev)
		open(dev, 'wb+') do |f|
			apm = APM.new(Buffer.new(f))
			part = apm.partition(apm.find_hfs)
			part.pwrite(0, "\0" * 4096)
		end
	end
end
