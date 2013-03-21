require 'rubygems'
require 'bindata'

require_relative 'structs'

class HFSPlus
	class ExtentDesc < BERecord
		uint32	:startBlock
		uint32	:blockCount
	end
	
	class ForkData < BERecord
		uint64	:logicalSize
		uint32	:clumpSize
		uint32	:totalBlocks
		array	:extents, :type => :extentDesc, :initial_length => 8
	end
	
	class Header < BERecord
		string	:signature, :length => 2
		uint16	:version
		uint32	:attributes
		string	:lastMountedVersion, :length => 4
		uint32	:journalInfoBlock
		
		uint32	:createDate
		uint32	:modifyDate
		uint32	:backupDate
		uint32	:checkedDate
		
		uint32	:fileCount
		uint32	:folderCount
		
		uint32	:blockSize
		uint32	:totalBlocks
		uint32	:freeBlocks
		
		uint32	:nextAllocation
		uint32	:rsrcClumpSize
		uint32	:dataClumpSize
		uint32	:nextCatalogID
		
		uint32	:writeCount
		uint64	:encodingsBitmap
		
		array	:finderInfo, :type => :uint32, :initial_length => 8
		
		forkData	:allocationFile
		forkData	:extentsFile
		forkData	:catalogFile
		forkData	:attributesFile
		forkData	:startupFile
	end
end
	