class Buffer
	# Basic operations
	def close; end
	def size; end
	def pread(off, size); end
	def pwrite(off, buf); end
	
	# Implement required IO operations for BinData::IO
	attr_reader :pos
	def initialize(&block)
		@pos = 0
	end
	def with(&block)
		if block
			block.(self)
			close
		end
	end
	
	def eof?; @pos >= size; end
	
	def seek(off, whence = IO::SEEK_SET)
		case whence
			when IO::SEEK_SET; @pos = off
			when IO::SEEK_CUR; @pos += off
			when IO::SEEK_END; @pos = size + off
		end
		return pos
	end
	
	def read(len = nil)
		if eof?
			return "" if len.nil? || len.zero?
			return nil
		end
		
		take = size - pos
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

class FileBuffer < Buffer
	def initialize(file, size = nil, &block)
		super()
		if file.respond_to? :read
			@io = file
		else
			@io = open(file, 'w+')
		end
		
		# Could use ioctls (eg: DKIOCGETBLOCKCOUNT), but too much trouble
		@size = size || find_size || 2**64
	end
	
	def find_size
		@io.seek(0, IO::SEEK_END)
		@io.pos.zero? ? nil : @io.pos
	end
	
	def io_seek(pos = nil); @io.seek(pos || @pos); end
	
	attr_reader :size
	def close; @io.close; end
	def pread(off, size); io_seek; @io.read(size); end
	def pwrite(off, buf); io_seek; @io.write(buf); end
end
