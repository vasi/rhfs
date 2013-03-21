require_relative 'structs'

class HFSPlus
class BTree
	def initialize(fork)
		@buf = fork
		
		# Read the header
		desc = @buf.st_read(NodeDesc)
		raise MagicException.new("Not a BTree header") \
			unless desc.kind == NodeHeader
		@header = @buf.st_read(Header, desc.num_bytes)
	end
	
	def nsize; @header.nodeSize; end
end
end
