require 'rubygems'
require 'bindata'

class BERecord < BinData::Record
	endian :big
end

# Apple Partition Map
# See IOApplePartitionScheme.h
class APM
	DefaultSector = 512
	DefaultEntries = 0x3f
	TypePMAP = 'Apple_Partition_Map'
	TypeHFS = 'Apple_HFS'
	
	class Block0 < BERecord
		Signature = 'ER'
		string	:sig, :length => 2, :initial_value => Signature
		uint16	:blkSize, :initial_value => 512
		uint32	:blkCount
		# ignore the rest
	end
	class Entry < BERecord
		Signature = 'PM'
		%w[Valid Allocated InUse Bootable Readable Writable].
			each_with_index { |n, i| const_set(n, 1 << i) }
		AutoMount = 0x40000000
		
		string	:signature, :length => 2, :initial_value => Signature
		uint16	:reserved_1
		uint32	:map_entries
		uint32	:pblock_start
		uint32	:pblocks		# size
		string	:name, :length => 32, :trim_padding => true
		string	:type, :length => 32, :trim_padding => true
		
		# optional
		uint32	:lblocks_start	# logical blocks (from zero)
		uint32	:lblocks
		uint32	:flags , :initial_value => Valid | Allocated
		
		# treat the rest as reserved
		string	:ignore_1, :length => 420
		hide	:reserved_1, :ignore_1
	end
	
	def blkSize; @block0.blkSize; end
	def count; @partitions.first.map_entries; end
	
	DONT_READ = false
	
	attr_accessor :block0, :partitions
	def initialize(buf, read = true)
		@buf = buf
		@block0 = Block0.new
		@partitions = []
		return unless read
		
		@block0 = @buf.st_read(Block0, 0)
		raise "Invalid APM header" unless block0.sig == Block0::Signature
		pmap = @buf.st_read(Entry, blkSize)
		@partitions = (1..pmap.map_entries).map do |i|
			p = @buf.st_read(Entry, i * blkSize)
			raise "Invalid APM entry" unless p.signature == Entry::Signature
			p
		end
	end
	
	def self.create(buf)
		sb = new(buf, DONT_READ)
		sb.block0.blkCount = buf.size / DefaultSector
		return sb
	end
	
	def write(fixup = true)
		@buf.st_write(block0, 0)
		partitions.each_with_index do |p,i|
			p.map_entries = partitions.count if fixup
			@buf.st_write(p, (i + 1) * blkSize)
		end
	end
	
	def partition(i)
		part = partitions[i]
		@buf.sub(part.pblock_start * blkSize, part.pblocks * blkSize)
	end
	
		
	# Find the index of the first hfs partition, if any
	def find_hfs
		partitions.find_index { |p| p.type == TypeHFS } \
			or raise "No HFS partition"
	end
end
