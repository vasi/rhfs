require 'rubygems'
require 'io/extra'

# This lets us have multiple sub-buffers based on the same file, with different
# position pointers.
class Buffer
	# Basic operations
	def close; end
	def size; end
	def pread(off, size); end
	def pwrite(off, buf); end
	
	# Initialization
	def initialize
		@pos = 0
	end
	
	def with(&block)
		if block
			block.(self)
			close
		end
	end
	
	def eof?; @pos >= size; end
	
	# Implement required IO operations for BinData::IO
	attr_reader :pos
	
	def seek(off, whence = IO::SEEK_SET)
		case whence
			when IO::SEEK_SET; @pos = off
			when IO::SEEK_CUR; @pos += off
			when IO::SEEK_END; @pos = size + off
		end
		return @pos
	end
	
	def read(len = nil)
		take = [size - pos, 0].max
		take = len if len && len < take
		ret = pread(pos, take)
		@pos += ret.size
		return ret
	end
	
	def write(buf)
		ret = pwrite(pos, buf)
		@pos += ret
		return ret
	end
	
	# Helpers for reading structures
	def st_read(st, off = 0)
		seek(off)
		st.read(self)
	end
	def st_write(st, off = 0)
		seek(off)
		st.write(self)
	end
	
	# Creation of sub-buffers
	def sub(off, size = nil, &block)
		SubBuffer.new(self, off, size, &block)
	end
end

class SubBuffer < Buffer
	def initialize(base, off, size = nil, &block)
		super()
		@base, @off = base, off
		@size = size || (base.size - off)
		with(&block)
	end
	attr_reader :size
	def pread(off, size); @base.pread(@off + off, size); end
	def pwrite(off, buf); @base.pwrite(@off + off, buf); end
end

class IOBuffer < Buffer
	DefaultSize = 2**64
	
	def initialize(io, size = nil, &block)
		super()
		if io.respond_to? :read
			@io = io
		else
			@io = open(io, 'w+')
		end
		
		# Could use ioctls (eg: DKIOCGETBLOCKCOUNT), but too much trouble
		@size = size || find_size || DefaultSize
		with(&block)
	end
	
	def find_size
		@io.seek(0, IO::SEEK_END)
		@io.pos.zero? ? nil : @io.pos
	end
	
	attr_reader :size
	def close; @io.close; end
	def pread(off, size); IO.pread(@io.fileno, size, off); end
	def pwrite(off, buf); IO.pwrite(@io.fileno, buf, off); end
end
