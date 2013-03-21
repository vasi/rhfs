class CompactSizer
	def size; end
	# Get max size such that (offset + size, offset + len) is unallocated
	def allocated_range(base, off, len); end
end

class BitmapSizer < CompactSizer
	def initialize(bitmap, block_size, blocks)
		@bm, @bsize, @count = bitmap, block_size, blocks
	end
	
	def size; @bsize * @count; end
	
	def allocated_range(base, off, len)
		bidx, _ = (off + len - 1).divmod(@bsize)
		bfirst, _ = off.divmod(@bsize)
		while bidx >= [bfirst, 0].max
			break if @bm.allocated?(bidx)
			bidx -= 1
		end
		
		alloc = (bidx + 1) * @bsize - off
		alloc = [[alloc, 0].max, len].min
		# return base.allocated_range(nil, off, alloc)
		return alloc
	end
end

class MultiSizer < CompactSizer
	class Sub < Struct.new(:offset, :sizer)
		def size; sizer.size; end
		def last; offset + size; end
	end
	
	attr_reader :size
	def initialize(size, **sizers)
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
		loop do
			s = @sizers[i]
			slast = (i >= 0 ? s.last : 0)
			if last >= slast
				return last - off # FIXME: base
			else
				if last > s.offset
					start = [off, s.offset].max
					# FIXME: base
					r = s.sizer.allocated_range(nil,
						start - s.offset, last - start)
					last = start + r
					return last unless r == 0
				end
				i -= 1
			end
		end
	end
end
