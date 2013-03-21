require_relative 'structs'

class HFSPlus
class BTree
	module KeyComparable
		def <=>(other); cmp_key <=> other.cmp_key; end
		include Comparable
	end
	
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
		class Record
			attr_reader :key
			def initialize(node, buf)
				@node, @buf = node, buf
				klen = buf.st_read(BinData::Uint16be)
				koff = klen.num_bytes
				@key = @node.key(buf.sub(koff, klen))
				@doff = koff + klen + (klen % 2 == 0 ? 0 : 1)
			end
			
			def data; @node.recdata(@buf.sub(@doff)); end

			def pretty_print_instance_variables
				[:@key, :data]
			end
		end
		
		def record(i); Record.new(self, super); end
		def key(b); @tree.key(b); end
		
		# Last index with a key <= k
		def find_in_node(k)
			idx = rec = nil
			each_with_index do |r, i|
				return idx, rec if r.key > k
				idx, rec = i, r
			end
			return idx, rec
		end
		
		def find(k)
			n, i, r = find_detailed(k)
			return (r && r.key == k) ? r : nil
		end
	end
	class IndexNode < KeyedNode
		def recdata(b); b.st_read(BinData::Uint32be); end
		
		def find_detailed(k)
			i, r = find_in_node(k)
			return self, nil, nil unless r
			return @tree.node(r.data).find_detailed(k)
		end
	end
	class LeafNode < KeyedNode
		def recdata(b); @tree.recdata(b); end
		def find_detailed(k)
			i, r = find_in_node(k)
			return self, i, r
		end
		
		def each_leaf(i, &block)
			n = self
			loop do
				block[n.record(i)]
				i += 1
				next if i < count
				
				break if n.desc.fLink == 0
				n = @tree.node(n.desc.fLink)
				i = 0
			end
		end
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
	def root; node(header.rootNode); end
	
	def key(buf); buf.read; end
	def recdata(buf); buf.read; end
	
	def find(k); root.find(k); end
end

class Catalog < BTree
	class Key
		attr_reader :parent, :name
		def initialize(parent, name)
			@parent = parent
			@name = name.encode(HFSPlus::UniStr::Encoding)
		end
		
		def self.read(buf)
			data = buf.st_read(KeyData)
			new(data.parentID.to_i, data.nodeName.to_s)
		end		
		
		def cmp_name
			# FIXME: better case folding; check for HFSX
			name.downcase.each_char.reject { |c| c.ord == 0 }.join
		end
		
		def cmp_key; [parent, cmp_name]; end
		include BTree::KeyComparable
	end
	
	def key(buf); Key.read(buf); end
	def recdata(buf)
		type = buf.st_read(BinData::Int16be)
		klass = case type
			when RecordFolder; Folder
			when RecordFile; File
			else; Thread
		end
		buf.st_read(klass)
	end
	
	def path(p)
		parts = p.split(%r{/})
		
		parent = IDRootFolder
		data = nil
		until parts.empty?
			name = parts.shift
			next if name.empty?
			
			rec = find(Key.new(parent, name)) or return nil
			data = rec.data
			return data if data.recordType == RecordFile
			
			parent = data.folderID
		end
		return data
	end
end

class ExtentsOverflow < BTree
	class Key < Struct.new(:fork, :file, :block)
		def self.read(buf)
			data = buf.st_read(KeyData)
			new(data.forkType.to_i, data.fileID.to_i, data.startBlock.to_i)
		end
		def cmp_key; [fork, file, block]; end
		include BTree::KeyComparable
	end
	
	def key(buf); Key.read(buf); end
	def recdata(buf)
		buf.st_read(BinData::Array.new(
			:type => :extentDesc, :initial_length => 8))
	end
	
	def each_record(cnid, alloc, fork = DataFork, &block)
		n, i, _ = root.find_detailed(Key.new(fork, cnid, alloc))
		n.each_leaf(i, &block)
	end
end
end
