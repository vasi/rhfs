class AllocationFinder
	def initialize(bitmap, block_size, blocks, offset = 0)
		@bm, @bsize, @count, @off = bitmap, block_size, blocks, offset
	end
	
	# Get max size such that (offset + size, offset + len) is unallocated
	def allocated_range(offset, len)
		return len if offset + len > @off + @bsize * @count
		
		bm_last = (offset + len - 1) - @off
		block, _ = bm_last.divmod(@bsize)
		block_first, _ = (offset - @off).divmod(@bsize)
		while block >= [block_first, 0].max
			break if @bm.allocated?(block)
			block -= 1
		end
		
		first_zero = @off + (block + 1) * @bsize
		return [[first_zero - offset, len].min, 0].max
	end
end
