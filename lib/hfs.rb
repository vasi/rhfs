require 'rubygems'
require 'bindata'

require_relative 'apm'

# Apple's HFS file system (not HFS+)
# See hfs_format.h
class HFS
	Sector = 512
	ReservedSectors = 2
	MDBOffset = ReservedSectors * Sector
	class MDB < BERecord
		Signature = 'BD'
		string	:sigWord, :length => 2
		string	:ignore_1, :length => 16
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
	def initialize(buf)
		@buf = buf
		@mdb = @buf.st_read(MDB, MDBOffset)
		raise MagicException.new("Invalid HFS partition") \
			unless mdb.sigWord == MDB::Signature
	end
	
	def write_mdb
		@buf.st_write(mdb, MDBOffset)
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
