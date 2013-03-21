require_relative 'buffer'
require_relative 'compact'

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
			@inline = @fd.extents.map { |e| e.blockCount }.reduce(:+)
		end
		def size; @fd.logicalSize; end
		
		def extent_group(alloc, &block)
			block.(0, @fd.extents) if alloc < @inline
			target = [alloc, @inline].max
			@fs.extents_overflow.each_record(@cnid, target, @type) do |r|
				block.(r.key.block, r.data)
			end
		end
		
		def bandlist(off, &block)
			b = off / @fs.asize
			extent_group(b) do |start, exts|
				exts.each do |e|
					if b < start + e.blockCount
						ee = Extent.new(@fs, e)
						block.(ee, start * @fs.asize)
					end
					start += e.blockCount
				end
			end
		end
		include BandedBuffer

		def pretty_print_instance_variables; instance_variables - [:@fs]; end
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
	def extents_overflow
		ExtentsOverflow.new(special(IDExtents, :extentsFile))
	end
	def catalog
		Catalog.new(special(IDCatalog, :catalogFile))
	end
	def allocation_file
		special(IDAllocation, :allocationFile)
	end
	
	def bitmap
		BufAllocBitmap.new(allocation_file, asize)
	end
	def sizer
		BitmapSizer.new(bitmap, asize, header.totalBlocks)
	end
	
	def path_fork(p, fork = DataFork)
		rec = catalog.path(p) or return nil
		return nil unless rec.recordType == Catalog::RecordFile
		ext = (fork == ResourceFork ? :resourceFork : :dataFork)
		return Fork.new(self, rec.fileID, fork, rec.send(ext))
	end
end
