#!/usr/bin/env rvm 2.0 do ruby
require 'rubygems'
require 'bindata'

class Buffer
	def initialize(p, off = 0, size = nil)
		if p.respond_to? :seek
			@io = p
		else
			@io = open(p)
		end
		@off = off
		@size = size || begin
			@io.seek(0, IO::SEEK_END)
			@io.pos - @off
		end
	end
	
	def seek(off)
		@io.seek(@off + off, IO::SEEK_SET)
	end
	
	def pread(off, size)
		seek(off)
		@io.read(size)
	end
	
	def st_read(st, off = 0)
		seek(off)
		st.read(@io)
	end
	def st_write(st, off = 0)
		seek(off)
		st.write(@io)
	end 
	
	def sub(off, size = nil)
		Buffer.new(@io, @off + off, size || @size - off)
	end
end

class Record < BinData::Record
	endian :big
end

# See IOApplePartitionScheme.h
class APM
	class Block0 < Record
		string	:sig, :length => 2
		uint16	:blkSize
		uint32	:blkCount
		# ignore the rest
	end
	class Entry < Record
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
end

# See hfs_format.h
class HFS
	Sector = 512
	ReservedSectors = 2
	class MDB < Record
		
	end
	
	def initialize(buf)
	end
end

require 'pp'
dev = ARGV.shift
buf = Buffer.new(dev)
apm = APM.new(buf)
pp apm
