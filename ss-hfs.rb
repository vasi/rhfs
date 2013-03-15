#!/usr/bin/env rvm 2.0 do ruby
require_relative 'lib/hfs'

require 'pp'

dev = ARGV.shift
buf = Buffer.new(dev)
apm = APM.new(buf)
hfs = HFS.new(apm.partition(1))
pp hfs
