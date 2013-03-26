require_relative 'buffer'

class CompactSizer
	def size; end
	# Get max size such that (offset + size, offset + len) is unallocated
	def allocated_range(base, off, len); end
	
	def sub(off, size = nil); SubSizer.new(self, off, size); end
end

# A sub-range of another sizer
class SubSizer < CompactSizer
	attr_reader :size
	def initialize(parent, off, size = nil)
		@parent, @off = parent, off
		@size = size || (parent.size - off)
	end
	def allocated_range(base, off, len)
		@parent.allocated_range(base, @off + off, len)
	end
end

# Read a buffer to look for zeros
class ReadSizer < CompactSizer
	DefaultBlockSize = Buffer::DefaultBlockSize
	def initialize(buf, block_size = DefaultBlockSize)
		@buf, @block_size = buf, block_size
	end
	def size; @buf.size; end
	
	def allocated_range(base, off, len)
		last = off + len
		while last > off
			start = [last - @block_size, off].max
			bsize = last - start
			block = @buf.pread(start, bsize)
			r = block.bytes.reverse.find_index { |b| b != 0 }
			return last - r - off if r
			last = start
		end
		return 0
	end
end

class AllocBitmap
	def initialize(cache_size)
		@cache_size = cache_size
		@cache_idx = @cache_buf = nil
	end
	
	def read(ci)
		# Subclass: read into @cache_buf
		@cache_idx = ci
	end
	
	def cache_bits; @cache_size * 8; end
	
	def cache(idx)
		ci = idx / cache_bits
		read(ci) unless @cache_idx == ci
	end
	
	def allocated?(idx)
		cache(idx)
		off = idx % cache_bits
		bit = 7 - (off % 8)
		byte = @cache_buf[off / 8]
		return ((byte >> bit) & 1) == 1
	end
end
class BufAllocBitmap < AllocBitmap
	def initialize(buf, cache_size)
		super(cache_size)
		@buf = buf
	end
	def read(ci)
		@cache_buf = @buf.pread(ci * @cache_size, @cache_size).bytes
		super
	end
end
class BitmapSizer < CompactSizer
	def initialize(bitmap, block_size, blocks)
		@bm, @bsize, @count = bitmap, block_size, blocks
	end
	
	def size; @bsize * @count; end
	
	def allocated_range(base, off, len)
		last = off + len
		while last > off
			bidx, _ = (last - 1).divmod(@bsize)
			start = [bidx * @bsize, off].max
			if @bm.allocated?(bidx)
				r = base.allocated_range(nil, start, last - start)
				return start + r - off unless r == 0
			end
			last = start
		end
		return 0
	end
end

# A sizer that assumes everything is allocated
class OpaqueSizer < CompactSizer
	attr_reader :size
	def initialize(size); @size = size; end
	def allocated_range(base, off, len); len; end
end

# Contains multiple sub-sizers over a background sizer
class MultiSizer < CompactSizer
	class Sub < Struct.new(:offset, :sizer)
		def size; sizer.size; end
		def last; offset + size; end
	end
	
	attr_reader :size
	def initialize(size, sizers = {})
		@size = size
		@sorted = false
		@sizers = sizers.map { |o,s| Sub.new(o, s) }
	end
	
	def sort
		return unless @sorted
		@sizers.sort_by { |s| s.offset }
		@sorted = true
	end
	
	def allocated_range(base, off, len)
		sort
		
		last = off + len
		i = @sizers.count - 1
		while last > off
			s = @sizers[i]
			slast = (i >= 0 ? s.last : 0)
			if last > slast
				r = base.sub(slast).allocated_range(nil, 0, last - slast)
				last = slast + r
				return last - off unless r == 0
			else
				if last > s.offset
					start = [off, s.offset].max
					r = s.sizer.allocated_range(base.sub(s.offset),
						start - s.offset, last - start)
					last = start + r
					return last - off unless r == 0
				end
				i -= 1
			end
		end
		return 0
	end
end
