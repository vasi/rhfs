#!/usr/bin/env rvm 2.0 do ruby
require_relative 'lib/ops'

require 'rubygems'
require 'trollop'
require 'pp'

SUB_COMMANDS = %{seed}
global_opts = Trollop::options do
	banner "manipulate disk images for use with SheepShaver and BasiliskII"
	stop_on SUB_COMMANDS
end

cmd = ARGV.shift
cmd_opts = case cmd
when "seed"
	disk = ARGV.shift
	Trollop::die "need an input disk to seed" unless disk
	Ops::seed_dev(disk)
else
	Trollop::die "unknown subcommand #{cmd.inspect}"
end
