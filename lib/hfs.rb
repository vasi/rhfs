require 'rubygems'
require 'bindata'

class BERecord < BinData::Record
	endian :big
end

# See IOApplePartitionScheme.h
class APM
	class Block0 < BERecord
		string	:sig, :length => 2
		uint16	:blkSize
		uint32	:blkCount
		# ignore the rest
	end
	class Entry < BERecord
		string	:signature, :length => 2
		uint16	:reserved_1
		uint32	:map_entries
		uint32	:pblock_start
		uint32	:pblocks		# size
		string	:name, :length => 32, :trim_padding => true
		string	:type, :length => 32, :trim_padding => true
		
		# optional
		uint32	:lblocks_start	# logical blocks (from zero)
		uint32	:lblocks
		uint32	:flags
		
		# treat the rest as reserved
		string	:ignore_1, :length => 420
		hide	:reserved_1, :ignore_1 
	end
	
	def blkSize; @block0.blkSize; end
	def count; @partitions.first.map_entries; end
	
	attr_accessor :block0, :partitions
	def initialize(buf)
		@buf = buf
		# FIXME: all at once?
		@block0 = @buf.st_read(Block0, 0)
		raise "Invalid APM header" unless block0.sig == 'ER'
		pmap = @buf.st_read(Entry, blkSize)
		@partitions = (1..pmap.map_entries).map do |i|
			p = @buf.st_read(Entry, i * blkSize)
			raise "Invalid APM entry" unless p.signature == 'PM'
			p
		end
	end
	
	def write
		@buf.st_write(block0, 0)
		partitions.each_with_index do |p,i|
			@buf.st_write(p, i * blkSize)
		end
	end
	
	def partition(i)
		part = partitions[i]
		@buf.sub(part.pblock_start * blkSize, part.pblocks * blkSize)
	end

	HFSType = 'Apple_HFS'
	
	# Find the index of the first hfs partition, if any
	def find_hfs
		partitions.find_index { |p| p.type == HFSType } \
			or raise "No HFS partition"
	end
end

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
	
	def write
		@buf.st_write(mdb, MDBOffset)
	end
end
