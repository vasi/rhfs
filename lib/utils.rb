class RHFS
	# Allow suffixes for MB, g, etc
	def self.size(s)
		suffixes = %w[k m g t]
		md = s.match(/^(\d+)(\D)?b?$/i) or raise "Unknown size #{s.inspect}"
		v = md[1].to_i
		if md[2]
			i = suffixes.find_index(md[2].downcase) \
				or raise "Unknown suffix #{md[2]}"
			v *= 1024 ** (i + 1)
		end
		return v
	end
end
