require_relative 'buffer'

require_relative 'hfsplus/structs'
require_relative 'hfsplus/btree'

# Apple's HFS+ format
# See hfs_format.h and Apple Tech Note 1150
class HFSPlus
	# HFS+ does not use sectors, but bytes
	HeaderOffset = 1024
	
	ForkData = 0
	ForkResource = 0xff
	
	
	class Extent < Buffer
		def initialize(fs, ext); @fs, @ext = fs, ext; end
		def size; @ext.blockCount * @fs.alloc_size; end
		def start; @ext.startBlock * @fs.alloc_size; end
		def pread(off, len); @fs.buf.pread(start + off, len); end
		def pwrite(off, buf); @fs.buf.pwrite(start + off, buf); end
	end
	
	class Fork < Buffer
		def initialize(hfsplus, cnid, type, fork_data)
			@fs, @cnid, @type, @fd = hfsplus, cnid, type, fork_data
		end
		def size; @fd.logicalSize; end
		
		def pread(off, len); end
		def pwrite(off, buf); end
	end
	
	
	attr_reader :header, :buf
	def initialize(buf)
		@buf = buf
		@header = @buf.st_read(Header, HeaderOffset)
	end
	def alloc_size; header.blockSize; end
end
