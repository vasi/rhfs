require 'rubygems'
require 'plist'

require 'tmpdir'

class Hdiutil
	Command = "/usr/bin/hdiutil"
	
	def self.go(subcmd, opts, &block)
		opts = opts.map { |x| x.to_s }
		block.([Command, subcmd, *opts])
		raise 'hdiutil failure' unless $?.success?
	end
	
	def self.run(subcmd, *opts); go(subcmd, opts) { |c| system(*c) }; end
	def self.plist(subcmd, *opts)
		pl = nil
		go(subcmd, opts) do |c|
			IO.popen(c) { |f| pl = f.read }
		end
		return Plist::parse_xml(pl)
	end
	
	def self.detach(dev); run('detach', dev); end
	def self.compact(img); run('compact', img); end
	
	def self.attach(img, &block)
		pl = plist('attach', '-plist', '-nomount', img)
		dev = pl['system-entities'].map { |e| e['dev-entry'] }.min
		if block
			block[dev]
			detach(dev)
		end
		return dev
	end
	
	def self.create(file, *args)
		tmp = Dir::Tmpname.create('', File.dirname(file)) { }
		pl = plist('create', *args, tmp)
		File.rename(pl.first, file)
	end
	
end
