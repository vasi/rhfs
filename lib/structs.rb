class BERecord < BinData::Record
	endian :big
end

class MagicException < Exception; end
