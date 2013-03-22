#!/usr/bin/env rvm 2.0 do ruby
require_relative 'lib/rhfs-tools'

require 'rubygems'
require 'trollop'
require 'pp'

def xbanner(name, usage, desc, extra = nil)
	usage = " #{usage}" unless usage.empty?
	extra = extra ? "#{extra}\n\n" : ""
	return <<-EOS
#{desc}

Usage: rhfs #{name} [options]#{usage}

#{extra}Options:
EOS
end

class Subcommand
	attr_reader :name, :desc, :parser
	def initialize(name, usage, desc, &block)
		@name, @desc = name, desc
		@parser = Trollop::Parser.new do
			banner xbanner(name, usage, desc)
			instance_eval(&block)
		end
	end
end

subcommands = [
	Subcommand.new(:create, "SIZE PATH",
			"Create a new sparsebundle disk image") do
		opt :partition, "Use a partition table"
		opt :format, "Include a valid HFS+ filesystem (Mac only)"
		opt :band, "Size of each band of the image", :type => :string,
			:default => "8m"
	end,
	Subcommand.new(:compact, "PATH", "Shrink a sparsebundle") { }
]

global_parser = Trollop::Parser.new do	
	size_max = subcommands.map { |s| s.name.size }.max
	extra = "Subcommands:\n" + subcommands.map do |s|
		"  %-*s: %s" % [size_max, s.name, s.desc]
	end.join("\n")
	banner xbanner('SUBCOMMAND', '',
		'Manipulate disk images for use with SheepShaver and BasiliskII',
		extra)
	
	version "rhfs 0.1 (c) 2013 Dave Vasilevsky"
	stop_on subcommands.map { |s| s.name.to_s }
end

sub = nil
Trollop.with_standard_exception_handling global_parser do
	opts = global_parser.parse ARGV
	cmd = ARGV.shift or raise Trollop::HelpNeeded
	sub = subcommands.find { |s| s.name.to_s == cmd } \
		or raise Trollop::CommandlineError.new(
			"unknown subcommand #{cmd.inspect}")
end

Trollop.with_standard_exception_handling sub.parser do
	opts = sub.parser.parse ARGV
	begin
		RHFSCommands.send(sub.name, opts, *ARGV)
	rescue ArgumentError
		raise Trollop::CommandlineError.new("Wrong number of arguments")
	end
end
