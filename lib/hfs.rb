require 'rubygems'
require 'bindata'

require_relative 'structs'
require_relative 'compact'

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
		
		blocks = mdb.nmAlBlks
		@bm_blocks = (blocks / 8.0).ceil
		@bitmap = BufAllocBitmap.new(
			@buf.sub(mdb.vbmSt * Sector, @bm_blocks), Sector)
	end
	
	def write_mdb
		@buf.st_write(mdb, MDBOffset)
	end
	
	def size
		(@bm_blocks + UnbitmappedBlocks) * Sector +
			mdb.nmAlBlks * mdb.alBlkSiz
	end
	
	def sizer
		MultiSizer.new(size,
			mdb.vbmSt => BitmapSizer.new(@bitmap, mdb.alBlkSiz, mdb.nmAlBlks))
	end
	
	def self.identify(buf)
		sigt = BinData::String.new(:length => 2)
		sig = buf.st_read(sigt, MDBOffset)
		case sig
		when MDB::Signature
			mdb = buf.st_read(MDB, MDBOffset)
			return mdb.embedSigWord == MDB::EmbedSignature ? :HFSWrapper : :HFS
		when 'H+'; return :HFSPlus
		when 'HX'; return :HFSX
		else; return nil
		end
	end
end
