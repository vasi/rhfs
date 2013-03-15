require 'rubygems'
require 'plist'

class Hdiutil
	Command = "/usr/bin/hdiutil"
	
	def self.run(subcmd, *opts)
		plist = nil
		IO.popen([Command, subcmd, *opts]) { |f| plist = f.read }
		raise 'hdiutil failure' unless $?.success?
		return Plist::parse_xml(plist)
	end
	
	def self.detach(dev)
		run('detach', dev)
	end
	
	def self.attach(img, &block)
		plist = run('attach', '-plist', '-nomount', img)
		dev = plist['system-entities'].map { |e| e['dev-entry'] }.min
		if block
			block[dev]
			detach(dev)
		end
		return dev
	end
	
	def self.create(file, *args)
		tmp = Dir::Tmpname.create('', File.dirname(file)) { }
		plist = run('create', *args, tmp)
		File.rename(plist.first, file)
	end
end
