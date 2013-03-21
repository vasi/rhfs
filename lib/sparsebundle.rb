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
			return "\0" * want unless @io
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
	DefaultBandSize = RHFS.size(DefaultBandSizeOpt)
	
	
	def initialize(path, rw = true, &block)
		@path, @rw = path, rw
		lock
		
		plist = Plist.parse_xml(File.join(path, PathPlist)) \
			or raise "Can't parse sparsebundle plist"
		PlistRequired.each do |k,v|
			plist[k] == v or raise "Sparsebundle plist unrecognized"
		end
		
		@size = plist[KeySize] or raise "Sparsebundle has no size"
		@band_size = plist[KeyBandSize] \
			or raise "Sparsebundle has no band size"
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
		raise "No lock file in sparsebundle" unless File.exist?(file)
		
		@lock = nil
		return unless RUBY_PLATFORM.include?("darwin")
		
		# See /usr/include/sys/fcntl.h
		o_shlock = 0x10
		o_exlock = 0x20
		o_nonblock = 0x4
	
		flags = o_nonblock
		if @rw
			flags ||= o_exlock | Fcntl::O_RDWR
		else
			flags ||= o_shlock | Fcntl::O_RDONLY
		end
		fd = IO.sysopen(file, flags, 0644)
		@lock = IO.new(fd)
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
	
	def bandify(off = 0, len = nil, &block)
		len ||= size - off
		idx = off / @band_size
		while len > 0 && idx < @bands.count do
			b = band(idx)
			boff = off % @band_size
			bsize = b.size
			blen = [len, bsize - boff].min
			block.(idx, b, boff, blen)
			
			off += blen
			len -= blen
			idx += 1
		end
	end
	
	def compact(sizer, base = nil)
		base ||= OpaqueSizer.new(size)
		bandify do |bidx, band, _, _|
			off = bidx * @band_size
			band.compact(bidx * @band_size, sizer, base)
		end
	end
	
	attr_reader :size
	def pread(off, len)
		ret = []
		bandify(off, len) do |_, band, boff, blen|
			r = band.pread(boff, blen)
			ret << r
			break unless r.bytesize == len
		end
		return ret.join
	end
		
	def pwrite(off, buf)
		ret = 0
		bandify(off, buf.bytesize) do |_, band, boff, blen|
			r = band.pwrite(boff, buf.byteslice(ret, blen))
			ret += r
			break unless r == blen
		end
		return ret
	end
	
	
	def pretty_print_instance_variables
		instance_variables - [:@bands]
	end
end
