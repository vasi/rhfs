class HFSPlus
	module KeyComparable
		def <=>(other); cmp_key <=> other.cmp_key; end
		include Comparable
	end
end
