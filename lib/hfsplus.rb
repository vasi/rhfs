require_relative 'buffer'

require_relative 'hfsplus/structs'
require_relative 'hfsplus/btree'

# Apple's HFS+ format
# See hfs_format.h and Apple Tech Note 1150
class HFSPlus
	# HFS+ does not use sectors, but bytes
	HeaderOffset = 1024
	
	class Extent < Buffer
		def initialize(fs, ext); @fs, @ext = fs, ext; end
		def size; @ext.blockCount * @fs.asize; end
		def start; @ext.startBlock * @fs.asize; end
		def pread(off, len); @fs.buf.pread(start + off, len); end
		def pwrite(off, buf); @fs.buf.pwrite(start + off, buf); end
	end
	
	class Fork < Buffer
		def initialize(hfsplus, cnid, type, fork_data)
			@fs, @cnid, @type, @fd = hfsplus, cnid, type, fork_data
		end
		def size; @fd.logicalSize; end
		
		def bandlist(off, &block)
			b = off / @fs.asize
			start = 0
			@fd.extents.each do |e|
				if b < e.endBlock
					ee = Extent.new(@fs, e)
					block.(ee, start * @fs.asize)
				end
				start += e.blockCount
			end
			raise "FIXME: Implement extent overflows"
		end
		include BandedBuffer
	end
	
	
	attr_reader :header, :buf
	def initialize(buf)
		# FIXME: wrapped
		@buf = buf
		@header = @buf.st_read(Header, HeaderOffset)
	end
	def asize; header.blockSize; end # Allocation block size
	
	def special(cnid, data)
		Fork.new(self, cnid, DataFork, @header.send(data))
	end
	def extents_file; BTree.new(special(IDExtents, :extentsFile)); end
end
