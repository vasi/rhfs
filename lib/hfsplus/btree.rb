require_relative 'structs'

class HFSPlus
class BTree
	class Node
		def self.create(tree, buf)
			desc = buf.st_read(NodeDesc)
			klass = case desc.kind
				when NodeLeaf; LeafNode
				when NodeIndex; IndexNode
				else; Node
			end
			klass.new(tree, buf, desc)
		end
		
		attr_reader :desc
		def initialize(tree, buf, desc)
			@tree, @buf, @desc = tree, buf, desc
			
			off_type = BinData::Array.new(:type => :uint16be,
				:initial_length => @desc.numRecords + 1)
		 	offs = @buf.st_read(off_type, tree.node_size - off_type.num_bytes)
			@offsets = offs.to_a.reverse
		end
		
		def count; @offsets.size - 1; end
		def record_buf(i)
			o = @offsets[i]
			@buf.sub(o, @offsets[i + 1] - o)
		end
		def record(i); record_buf(i); end
		
		def each(&block)
			 0.upto(count - 1) { |i| block.(record(i)) }
		end
		include Enumerable
		
		def pretty_print_instance_variables; instance_variables - [:@buf]; end
	end
	class KeyedNode < Node
		class Data
			class KeyLength < BERecord
				uint16	:len
			end
			
			attr_reader :key
			def initialize(node, buf)
				@node, @buf = node, buf
				klen = buf.st_read(BinData::Uint16be)
				koff = klen.num_bytes
				@key = @node.key(buf.sub(koff, klen))
				@doff = koff + klen + (klen % 2 == 0 ? 0 : 1)
			end
			
			def data; @node.recdata(@buf.sub(@doff)); end
		end
		
		def record(i); Data.new(self, super); end
		def key(b); @tree.key(b); end
	end
	class IndexNode < KeyedNode
		def recdata(b); b.st_read(BinData::Uint32be); end
	end
	class LeafNode < KeyedNode
		def recdata(b); @tree.recdata(b); end
	end
	
	
	attr_reader :header
	def initialize(fork)
		@buf = fork
		
		# Read the header
		desc = @buf.st_read(NodeDesc)
		raise MagicException.new("Not a BTree header") \
			unless desc.kind == NodeHeader
		@header = @buf.st_read(Header, desc.num_bytes)
	end
	
	def pretty_print_instance_variables; instance_variables - [:@buf]; end

	def node_size; @header.nodeSize; end
	def node(i); Node.create(self, @buf.sub(i * node_size)); end
	
	def key(buf); buf.read; end
	def recdata(buf); buf.read; end
end

class Catalog < BTree
	class CatalogKey < Struct.new(:parentID, :nodeName)
		class Data < BERecord
			uint32	:parentID
			uniStr	:nodeName
		end
		NameEncoding = 'UTF-16BE'
		
		def self.read(buf)
			data = buf.st_read(Data)
			new(data.parentID.to_i,
				data.nodeName.unicode.to_s.force_encoding(NameEncoding))
		end
		
		
		def case_name
			# FIXME: better case folding; check for HFSX
			nodeName.downcase
		end
		
		def cmp_key; [parentID, case_name]; end
		def <=>(other); cmp_key <=> other.cmp_key; end
	end
	
	def key(buf); CatalogKey.read(buf); end
end
end
