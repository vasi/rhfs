require 'rubygems'
require 'plist'

require 'fcntl'
require 'fileutils'

require_relative 'buffer'
require_relative 'utils'

class Sparsebundle < Buffer
	class Band < Buffer
		attr_reader :size
		def initialize(path, size, rw = true)
			@path, @size, @rw = path, size, rw
			@io = nil
			open if File.exist?(@path)
		end
		def alloc; @io ? @io.size : 0; end
		def open; @io ||= IOBuffer.new(@path, @rw); end
		def close; @io.close if @io; @io = nil; end
				
		def pread(off, len)
			want = [len, @size - off].min
			return "\0" * want if alloc < off
			avail = [want, alloc - off].min
			return @io.pread(off, avail) + "\0" * (want - avail)
		end
		
		def pwrite(off, buf)
			len = [buf.bytesize, @size - off].min
			buf = buf.byteslice(0, len)
			
			# Don't write where unnecessary
			zeros = buf.match(/\0*$/)[0].size
			nz = len - zeros
			return buf.bytesize if !@io && nz == 0
			
			open # forced create
			space = [alloc - off, 0].max
			want = [nz, [space, len].min].max
			ret = @io.pwrite(off, buf.byteslice(0, want))
			return len if ret == want
			return ret
		end
		
		def zero(off, len)
			if off + len < alloc
				super
			elsif off < alloc
				truncate(off)
			end
		end
		
		def compact(off, sizer, base)
			len = alloc
			return if len == 0 # as small as it gets
			
			range = sizer.allocated_range(base, off, len)
			truncate(range) if range < len
		end
		
		def truncate(len)
			return if len >= alloc
			if len == 0
				File.unlink(@path)
				close
			else
				@io.truncate(len)
			end
		end
		
		def copy_band(dest, off)
			@io.copy(dest.sub(off)) if alloc != 0
			dest.zero(off + alloc, size - alloc) if size > alloc
		end
	end
	
	
	KeyVersion = "CFBundleInfoDictionaryVersion"
	ValueVersion = "6.0"
	KeySize = "size"
	KeyBandSize = "band-size"	
	PlistRequired = {
		"diskimage-bundle-type" => "com.apple.diskimage.sparsebundle",
		"bundle-backingstore-version" => 1,
	}
	
	PathBands = "bands"
	PathPlist = "Info.plist"
	PathLock = "token"
	
	Sector = 512
	DefaultBandSizeOpt = "8m"
	DefaultBandSize = RHFS.size_spec(DefaultBandSizeOpt)
	
	
	attr_reader :size, :band_size
	def initialize(path, rw = true, &block)
		@path, @rw = path, rw
		
		plist = Plist.parse_xml(File.join(path, PathPlist)) \
			or raise MagicException.new("Can't parse sparsebundle plist")
		PlistRequired.each do |k,v|
			plist[k] == v or \
				raise MagicException.new("Sparsebundle plist unrecognized")
		end
		
		@size = plist[KeySize] or raise "Sparsebundle has no size"
		@band_size = plist[KeyBandSize] \
			or raise "Sparsebundle has no band size"
		
		lock
		
		band_count = @size / @band_size
		@bands = [nil] * band_count
		
		with(&block)
	end

	def self.create(path, size, band_size = DefaultBandSize, &block)
		raise "Band size in a sparsebundle must be a multiple of sector size" \
			if band_size % Sector != 0
		raise "Total sparsebundle size must be a multiple of sector size" \
			if size % Sector != 0
		band_sectors = band_size / Sector
		raise "Sparsebundle bands must be between 2048 and 16777216 sectors" \
			if band_sectors < 2048 || band_sectors > 16777216 
		
		plist = PlistRequired.merge({
			KeyVersion => ValueVersion,
			KeySize => size,
			KeyBandSize => band_size,
		})
		
		FileUtils.mkdir(path)
		FileUtils.mkdir(File.join(path, PathBands))
		FileUtils.touch(File.join(path, PathLock))
		plist.save_plist(File.join(path, PathPlist))
		return new(path, &block)
	end
	
	def self.create_approx(path, size, band_size = DefaultBandSize, &block)
		band_sectors = (band_size.to_f / Sector).round
		band_sectors = [2048, [16777216, band_sectors].min].max
		size = Sector * (size.to_f / Sector).ceil
		create(path, size, Sector * band_sectors, &block)
	end
	
	def lock
		file = File.join(@path, PathLock)
		@lock = open(file, @rw ? File::RDWR : File::RDONLY)
		flags = File::LOCK_NB | (@rw ? File::LOCK_EX : File::LOCK_SH)
		unless @lock.flock(flags)
			@lock.close
			@lock = nil
			raise "Sparsebundle is locked"
		end
	end

	def close
		@lock.close if @lock
		@bands.each { |b| b.close if b }
	end
	
	def band(idx)
		raise "Nonexistent band in sparsebundle" if idx >= @bands.count
		@bands[idx] ||= begin
			path = File.join(@path, PathBands, "%x" % idx)
			size = [@band_size, @size - idx * @band_size].min
			Band.new(path, size, @rw)
		end
	end
		
	def compact(sizer, base = nil)
		base ||= OpaqueSizer.new(size)
		bandify do |band, _, _, band_off|
			band.compact(band_off, sizer, base)
		end
	end
	
	
	def bandlist(off, &block)
		(off / @band_size).upto(@bands.count - 1) do |i|
			block.(band(i), i * @band_size)
		end
	end
	include BandedBuffer
	
	
	def pretty_print_instance_variables
		instance_variables - [:@bands]
	end
end
