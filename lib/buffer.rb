# This lets us have multiple sub-buffers based on the same file, with different
# position pointers.
class Buffer
	DefaultBlockSize = 512
	
	# Basic operations
	def close; end
	def size; end
	def pread(off, len); end
	def pwrite(off, buf); end
	
	# Optional operation
	def zero(off, len)
		each_block(off, len) { |o, l| pwrite(o, "\0" * l) }
	end
	
	def copy(dest, bsize = DefaultBlockSize)
		each_block(0, size, bsize) do |off, len|
			dest.pwrite(off, pread(off, len))
		end
	end
	
	
	# Initialization
	def initialize
		@pos = 0
	end
	
	def with(&block)
		if block
			r = block.(self)
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
		@pos += ret.bytesize
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
	
	# Helper for doing operations in blocks
	def each_block(off = 0, len = nil, bsize = DefaultSize, &block)
		len ||= size - off
		last = off + len
		while off < last
			blen = [len, bsize].min
			block.(off, blen)
			off += blen
		end
	end
end

class SubBuffer < Buffer
	def initialize(base, off, size = nil, &block)
		super()
		@base, @off = base, off
		@size = size
		with(&block)
	end
	def size; @size || (@base.size - @off); end
	def pread(off, len); @base.pread(@off + off, len); end
	def pwrite(off, buf); @base.pwrite(@off + off, buf); end
end

class IOBuffer < Buffer
	DefaultSize = 2**64
	
	def initialize(io, rw = true, size = nil, &block)
		super()
		if io.respond_to? :read
			@io = io
		else
			@io = open(io, rw ? (File::RDWR | File::CREAT) : File::RDONLY)
		end
		
		@size_spec = size
		find_size
		with(&block)
	end
	
	def find_size
		if @size_spec
			@size = @size_spec
			return
		elsif File.file?(@io)
			@io.seek(0, IO::SEEK_END)
			@size = @io.pos
		else
			# Could use ioctls (eg: DKIOCGETBLOCKCOUNT) on devices,
			# but too much trouble
			@size = DefaultSize
		end
	end
	
	attr_reader :size
	def close; @io.close; end
	def pread(off, len)
		@io.seek(off, IO::SEEK_SET)
		@io.read(len)
	end
	def pwrite(off, buf)
		@io.seek(off, IO::SEEK_SET)
		ret = @io.write(buf)
		@size = [@size, off + ret].max
		return ret
	end
	
	def truncate(len)
		@io.truncate(len)
		find_size
	end
	
	def zero(off, len)
		wlast = [off + len, size].min
		super(off, wlast - off) if off < wlast
		truncate(off + len) if off + len > size
	end
end

module BandedBuffer
	def bandify(off = 0, len = nil, &block)
		len ||= size - off
		
		bandlist(off) do |b, band_off|
			boff = off - band_off
			bsize = b.size
			blen = [len, bsize - boff].min
			block.(b, boff, blen, band_off)			
			off += blen
			len -= blen
			return if len == 0
		end
	end
	
	def pread(off, len)
		ret = []
		bandify(off, len) do |band, boff, blen, _|
			r = band.pread(boff, blen)
			ret << r
			break unless r.bytesize == len
		end
		return ret.join
	end
		
	def pwrite(off, buf)
		ret = 0
		bandify(off, buf.bytesize) do |band, boff, blen, _|
			r = band.pwrite(boff, buf.byteslice(ret, blen))
			ret += r
			break unless r == blen
		end
		return ret
	end
	
	def zero(off, len)
		bandify(off, len) do |band, boff, blen, _|
			band.zero(boff, blen)
		end
	end
	
	def copy(dest)
		bandify do |band, _, _, band_off|
			band.copy_band(dest, band_off)
		end
	end
end
