#!/usr/bin/env rvm 2.0 do ruby
require_relative 'lib/ops'

require 'rubygems'
require 'trollop'
require 'pp'

def xbanner(name, usage, desc, extra = nil)
	usage = " #{usage}" unless usage.empty?
	extra = extra ? "#{extra}\n\n" : ""
	return <<-EOS
#{desc}

Usage: ss-hfs #{name} [options]#{usage}

#{extra}Options:
EOS
end

Subcommand = Struct.new(:name, :usage, :desc, :parser)

subcommands = [
	Subcommand.new(:seed, "(DEVICE | IMAGE)", "Create a shrinkable disk image",
		Trollop::Parser.new)
]

global_parser = Trollop::Parser.new do	
	size_max = subcommands.map { |s| s.name.size }.max
	extra = "Subcommands:\n" + subcommands.map do |s|
		"  %-*s: %s" % [size_max, s.name, s.desc]
	end.join("\n")
	banner xbanner('SUBCOMMAND', '',
		'Manipulate disk images for use with SheepShaver and BasiliskII',
		extra)
	
	version "ss-hfs 0.1 (c) 2013 Dave Vasilevsky"
	stop_on subcommands.map { |s| s.name.to_s }
end

sub = nil
Trollop.with_standard_exception_handling global_parser do
	begin
		opts = global_parser.parse ARGV
		cmd = ARGV.shift or raise Trollop::HelpNeeded
		sub = subcommands.find { |s| s.name.to_s == cmd } \
			or raise Trollop::CommandlineError.new("unknown subcommand #{cmd.inspect}")
	rescue Trollop::HelpNeeded
		global_parser.educate
		exit # FIXME
	end
end

Trollop.with_standard_exception_handling sub.parser do
	sub.parser.banner xbanner(sub.name, sub.usage, sub.desc)
	opts = sub.parser.parse ARGV
	begin
		Ops.send(sub.name, opts, *ARGV)
	rescue ArgumentError
		raise Trollop::CommandlineError.new("Wrong number of arguments")
	end
end