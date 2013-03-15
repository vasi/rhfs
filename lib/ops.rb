require_relative 'hfs'

# Extensions
class APM
	HFSType = 'Apple_HFS'
	
	# Find the index of the first hfs partition, if any
	def find_hfs
		partitions.find_index { |p| p.type == HFSType } \
			or raise "No HFS partition"
	end
end

class Ops
	# Corrupt an HFS partition, so MacOS offers to format it
	def self.seed_dev(dev)
		open(dev, 'wb+') do |f|
			apm = APM.new(Buffer.new(f))
			part = apm.partition(apm.find_hfs)
			part.pwrite(0, "\0" * 4096)
		end
	end
end
