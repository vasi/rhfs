require_relative 'compact'
require_relative 'structs'

# Apple's HFS file system (not HFS+)
# See hfs_format.h
class HFS
	Sector = 512
	ReservedSectors = 2
	MDBOffset = ReservedSectors * Sector
	UnbitmappedBlocks = 5	# boot blocks, MDB, alt MDB, unused
	
	class MDB < BERecord
		Signature = 'BD'
		AtrbUnmounted = 1 << 8
		
		string	:sigWord, :length => 2
		uint32	:crDate
		uint32	:lsMod
		uint16	:atrb
		uint16	:nmFls
		uint16	:vbmSt
		uint16	:allocPtr
		uint16	:nmAlBlks
		uint32	:alBlkSiz
		uint32	:clpSiz
		uint16	:alBlSt
		string	:ignore_2, :length => 94
		
		EmbedSignature = 'H+'
		string	:embedSigWord, :length => 2
		uint16	:embedStartBlock
		uint16	:embedBlockCount
	end
	
	attr_accessor :mdb
	attr_reader :bitmap
	def initialize(buf)
		@buf = buf
		@mdb = @buf.st_read(MDB, MDBOffset)
		raise MagicException.new("Invalid HFS partition") \
			unless mdb.sigWord == MDB::Signature
		
		@bm_blocks = (mdb.nmAlBlks / 8.0).ceil
	end
	
	def write_mdb
		@buf.st_write(mdb, MDBOffset)
	end
	
	def asize; mdb.alBlkSiz; end
	def size
		(@bm_blocks + UnbitmappedBlocks) * Sector + mdb.nmAlBlks * asize
	end
	
	def bitmap
		BufAllocBitmap.new(@buf.sub(mdb.vbmSt * Sector), Sector)
	end
	def sizer
		MultiSizer.new(size, mdb.alBlSt * Sector =>
			BitmapSizer.new(bitmap, asize, mdb.nmAlBlks))
	end
	
	def embed_offset
		mdb.alBlSt * Sector + mdb.embedStartBlock * asize
	end
	def embed_size
		mdb.embedBlockCount * asize
	end
end
