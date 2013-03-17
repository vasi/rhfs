require 'rubygems'
require 'bindata'

require_relative 'apm'
require_relative 'compact'

# Apple's HFS file system (not HFS+)
# See hfs_format.h
class HFS
	Sector = 512
	ReservedSectors = 2
	MDBOffset = ReservedSectors * Sector
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
	
	class AllocationBitmap
		Sector = HFS::Sector
		BitsPerSec = Sector * 8
		
		def initialize(buf)
			@buf = buf
			@cur_sec = @cache = nil
		end
		
		def read(sec)
			@cache = @buf.pread(sec * Sector, Sector).bytes
			@cur_sec = sec
		end
		
		def cache(idx)
			sector = idx / BitsPerSec
			return if sector == @cur_sec
			read(sector)
		end
		
		def allocated?(idx)
			cache(idx)
			off = idx % BitsPerSec
			bit = 7 - (off % 8)
			byte = @cache[off / 8]
			return ((byte >> bit) & 1) == 1
		end
	end

	
	attr_accessor :mdb
	attr_reader :bitmap
	def initialize(buf)
		@buf = buf
		@mdb = @buf.st_read(MDB, MDBOffset)
		raise MagicException.new("Invalid HFS partition") \
			unless mdb.sigWord == MDB::Signature
		
		blocks = mdb.nmAlBlks
		@bitmap = AllocationBitmap.new(@buf.sub(mdb.vbmSt * Sector,
			(blocks + 7) / 8))
	end
	
	def write_mdb
		@buf.st_write(mdb, MDBOffset)
	end
	
	def allocation_finder
		AllocationFinder.new(@bitmap, mdb.alBlkSiz, mdb.nmAlBlks,
			mdb.vbmSt * Sector)
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
