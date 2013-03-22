require_relative 'apm'
require_relative 'hfs'
require_relative 'hfsplus'
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
	
	def self.compact_prep_vol(buf)
		return unless HFSPlus.identify(buf) == :HFSWrapper
		
		# Add the flag whose absence gives hdiutil trouble
		hfs = HFS.new(buf)
		hfs.mdb.atrb |= HFS::MDB::AtrbUnmounted
		hfs.write_mdb
	end
	
	def self.compact(path)
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
