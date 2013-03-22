require 'rubygems'
require 'bindata'

require_relative '../structs'

class HFSPlus
	DataFork = 0
	ResourceFork = 0xff
	
	IDRootFolder = 2
	IDExtents = 3
	IDCatalog = 4
	IDAllocation = 6
	
	class Point16 < BERecord
		int16	:v
		int16	:h
	end
	
	class Rect16 < BERecord
		int16	:top
		int16	:left
		int16	:bottom
		int16	:right
	end
	
	class UniStr < BERecord
		uint16	:len, :value => lambda { :unicode.length / 2 }
		string	:unicode, :read_length => lambda { len * 2 } # UTF-16
		
		Encoding = 'UTF-16BE'
		def to_s; unicode.force_encoding(Encoding); end
	end
	
	
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
		HFSPlusSignature = "H+"
		HFSXSignature = "HX"
		
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
	
	
	class BTree
		NodeLeaf = -1
		NodeIndex = 0
		NodeHeader = 1
		NodeMap = 2
		
		class NodeDesc < BERecord
			uint32	:fLink
			uint32	:bLink
			int8	:kind
			uint8	:height
			uint16	:numRecords
			uint16	:reserved
		end
		
		class Header < BERecord
			uint16	:treeDepth
			uint32	:rootNode
			uint32	:leafRecords
			uint32	:firstLeafNode
			uint32	:lastLeafNode
			uint16	:nodeSize
			uint16	:maxKeyLength
			uint32	:totalNodes
			uint32	:freeNodes
			uint16	:reserved1
			uint32	:clumpSize
			uint8	:btreeType
			uint8	:keyCompareType
			uint32	:attributes
			array	:reserved3, :type => :uint32, :initial_length => 16
		end
	end
	
	class Catalog < BTree
		class KeyData < BERecord
			uint32	:parentID
			uniStr	:nodeName
		end
		
		RecordFolder = 1
		RecordFile = 2
		RecordThreadFolder = 3
		RecordThreadFile = 4
		
		class BSDInfo < BERecord
			uint32	:ownerID
			uint32	:groupID
			uint8	:adminFlags
			uint8	:ownerFlags
			uint16	:fileMode
			uint32	:special
		end
		class FolderInfo < BERecord
			rect16	:windowBounds
			uint16	:finderFlags
			point16	:location
			uint16	:reserved
		end
		class FileInfo < BERecord
			string	:fileType, :length => 4
			string	:fileCreator, :length => 4
			uint16	:finderFlags
			point16	:location
			uint16	:reserved
		end
		class ExtFolderInfo < BERecord
			point16	:scrollPosition
			uint32	:dateAdded
			uint16	:extFinderFlags
			uint16	:reserved2
			uint32	:putAwayFolderID
		end
		class ExtFileInfo < BERecord
			uint32	:reserved1
			uint32	:dateAdded
			uint16	:extFinderFlags
			uint16	:reserved2
			uint32	:putAwayFolderID
		end
		
		class Folder < BERecord
			int16	:recordType
			uint16	:flags
			uint32	:valence
			uint32	:folderID
			uint32	:createDate
			uint32	:modifyDate
			uint32	:backupDate
			bsdInfo	:permissions
			folderInfo		:userInfo
			extFolderInfo	:finderInfo
			uint32	:textEncoding
			uint32	:reserved
		end
		class File < BERecord
			int16	:recordType
			uint16	:flags
			uint32	:reserved1
			uint32	:fileID
			uint32	:createDate
			uint32	:contentModDate
			uint32	:attributeModDate
			uint32	:accessDate
			uint32	:backupDate
			bsdInfo	:permissions
			fileInfo	:userInfo
			extFileInfo	:finderInfo
			uint32		:textEncoding
			uint32		:reserved2
			
			forkData	:dataFork
			forkData	:resourceFork
		end
		class Thread < BERecord
			int16	:recordType
			uint16	:reserved
			uint32	:parentID
			uniStr	:nodeName
		end
	end
	
	class ExtentsOverflow < BTree
		class KeyData < BERecord
			uint8	:forkType
			uint8	:pad
			uint32	:fileID
			uint32	:startBlock
		end
	end
end
