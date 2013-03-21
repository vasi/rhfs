require_relative 'apm'

require_relative 'hfsplus/structs'
require_relative 'hfsplus/btree'

# Apple's HFS+ format
# See hfs_format.h and Apple Tech Note 1150
class HFSPlus
	# HFS+ does not use sectors, but bytes
	HeaderOffset = 1024
	
	
	
	
	
	def initialize(buf)
		@buf = buf
		@header = @buf.st_read(Header, HeaderOffset)
	end
end
