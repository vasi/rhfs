require 'sparsebundle'
require 'hfsplus'

def enc(s)
	e = $stdout.external_encoding || Encoding.default_external
	s.encode(e, :undef => :replace)
end

def list(cat, cnid, path = '')
	path = enc(path)
	r = cat.find(cat.make_key(cnid)) or return
	r.each_leaf(:skip_self) do |c|
		name = c.key.name.to_s
		break if name.empty?
		
		cpath = [path, enc(name)].join('/')
		puts cpath
		next if c.data.recordType != HFSPlus::Catalog::RecordFolder
		list(cat, c.data.folderID, cpath)
	end
end

Sparsebundle.new(ARGV.shift) do |sb|
	fs = HFSPlus.new(sb)
	catalog = fs.catalog
	root = HFSPlus::IDRootFolder
	list(catalog, root)
end
