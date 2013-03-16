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
		string	:sigWord, :length => 2
		string	:ignore_1, :length => 16
		uint16	:nmAlBlks
		uint32	:alBlkSiz
		uint32	:clpSiz
		uint16	:alBlSt
		string	:ignore_2, :length => 94
		
		string	:embedSigWord, :length => 2
		uint16	:embedStartBlock
		uint16	:embedBlockCount
	end
	
	attr_accessor :mdb
	def initialize(buf)
		@buf = buf
		@mdb = @buf.st_read(MDB, MDBOffset)
		raise "Invalid HFS partition" unless mdb.sigWord == 'BD'
	end
	
	def write_mdb
		@buf.st_write(mdb, MDBOffset)
	end
end
