require 'tmpdir'

require_relative 'apm'
require_relative 'hfs'
require_relative 'hdiutil'
require_relative 'sparsebundle'
require_relative 'utils'

class RHFS
	TypeUnwrapped = 'RHFS_Unwrap'
	
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
		args << '-layout' << (partitioned ? 'SPUD' : 'NONE')
		Hdiutil.create(path, *args)
	end
	
	def self.compact_prep_vol(buf)
		return unless HFS.identify(buf) == :HFSWrapper
		
		# Add the flag whose absence gives hdiutil trouble
		hfs = HFS.new(buf)
		hfs.mdb.atrb |= HFS::MDB::AtrbUnmounted
		hfs.write_mdb
	end
	
	def self.compact(path)
		# Fixup hdiutil breakage
		Sparsebundle.new(path) do |sb|
			compact_prep_vol(sb)
			begin
				apm = APM.new(sb)
			rescue MagicException
				break
			end
			apm.count.times do |i|
				next unless apm.partitions[i].type == APM::TypeHFS
				compact_prep_vol(apm.buffer(i))
			end
		end
		
		Hdiutil.compact(path)
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
		RHFS.send(method, path, opts[:partition], size, band_size)
	end
	
	def self.compact(opts, *args)
		raise Trollop::CommandlineError.new("Bad number of arguments") \
			unless args.size == 1
		path, = *args
		RHFS.compact(path)
	end
end
