require_relative 'compact'
require_relative 'hfs'
require_relative 'hfsplus'
require_relative 'structs'

# Apple Partition Map
# See IOApplePartitionScheme.h
class APM
	DefaultSector = 512
	DefaultEntries = 0x3f
	TypePMAP = 'Apple_partition_map'
	TypeHFS = 'Apple_HFS'
	
	class Block0 < BERecord
		Signature = 'ER'
		string	:sig, :length => 2, :initial_value => Signature
		uint16	:blkSize, :initial_value => DefaultSector
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
		
		def add_flags(*fs)
			fs.each do |f|
				self.flags |= f.respond_to?(:|) ? f : self.class.const_get(f)
			end
		end
	end
	
	
	DONT_READ = false
	def initialize(buf, read = true)
		@buf = buf
		@block0 = Block0.new
		@block0.blkCount = buf.size / @block0.blkSize
		@entries = []
		return unless read
		
		@block0 = @buf.st_read(Block0, 0)
		raise MagicException.new("Invalid APM header") \
			unless block0.sig == Block0::Signature
		pmap = @buf.st_read(Entry, blkSize)
		@entries = (1..pmap.map_entries).map do |i|
			pt = @buf.st_read(Entry, i * blkSize)
			raise "Invalid APM entry" unless pt.signature == Entry::Signature
			pt
		end
	end	
	
	attr_accessor :block0
	def blkSize; @block0.blkSize; end
	def count; @entries.count; end
	def size; blkSize * @block0.blkCount; end
	
	def next_block; @entries.map { |e| e.pblock_start + e.pblocks }.max; end
	
	
	Filesystems = [HFSPlus, HFS]
	class Partition
		attr_reader :blkSize, :index, :entry
		def initialize(basebuf, bsize, index, entry)
			@basebuf, @blkSize, @index, @entry = basebuf, bsize, index, entry
		end
		def offset; entry.pblock_start * blkSize; end
		def size; entry.pblocks * blkSize; end
		def buffer; @basebuf.sub(offset, size); end
		def type; entry.type; end
		
		def filesystem
			buf = buffer
			Filesystems.each do |kl|
				begin
					fs = kl.new(buf)
					return fs
				rescue MagicException
				end
			end
			return nil
		end
	end
	def partition(i); Partition.new(@buf, blkSize, i, @entries[i]); end
	def partitions; count.times { |i| yield partition(i) }; end
	
	
	def sizer
		subs = {}
		partitions do |pt|
			fs = pt.filesystem or next
			subs[pt.offset] = fs.sizer
		end
		MultiSizer.new(size, subs)
	end
	
	
	def add(type, **opts)
		if @entries.empty? # Need an entry for the partition map itself
			@entries << Entry.new(:type => TypePMAP, :pblock_start => 1,
				:pblocks => DefaultEntries)
		end
		
		len = opts[:len]
		flags = opts[:flags]
		
		blocks = len ? len / blkSize : @block0.blkCount
		start = next_block
		blocks = [blocks, @block0.blkCount - start].min
		
		entry = Entry.new(:type => type, :pblock_start => start,
			:pblocks => blocks)
		entry.add_flags(*flags) if flags
		
		@entries << entry
		return partition(count - 1)
	end
	
	def write(fixup = true)
		@buf.st_write(block0, 0)
		
		# Zero out the partition map first
		partitions do |pt|
			next unless pt.type == TypePMAP
			pt.buffer.pwrite(0, "\0" * pt.size)
		end
		
		# Write the entries
		partitions do |pt|
			pt.entry.map_entries = count if fixup
			@buf.st_write(pt.entry, (pt.index + 1) * blkSize)
		end
	end
end
