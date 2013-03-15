require 'tmpdir'

require_relative 'hfs'
require_relative 'hdiutil'

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
	def self.seed(opts, file)
		if opts[:create]
			size = opts[:create]
			size += 'm' if size.match(/^\d+$/) # default to MB
			
			args = %w{-plist -type SPARSEBUNDLE -layout SPUD -fs HFS+}
			args << '-size' << size
			args.concat(opts[:extra_args].split) if opts[:extra_args]
			Hdiutil.create(file, *args)
			Hdiutil.attach(file) { |d| seed_device(d) }
		else
			seed_device(file)
		end
	end
	
	def self.seed_device(dev)
		open(dev, 'wb+') do |f|
			apm = APM.new(Buffer.new(f))
			part = apm.partition(apm.find_hfs)
			part.pwrite(0, "\0" * 4096)
		end
	end
end
