#!/usr/bin/ruby -w

#    This file is part of Openplacos.
#
#    Openplacos is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    Openplacos is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with Openplacos.  If not, see <http://www.gnu.org/licenses/>.
require "rubygems"
require 'xmlrpc/server'
require "openplacos"
require "micro-optparse"

options = Parser.new do |p|
  p.banner = "This is openplacos plugins for xmlrpc server"
  p.version = "xmlrpc 1.0"
  p.option :port, "the server port", :default => 8080
end.process!(ARGV)

plugin = Openplacos::Plugin.new

plugin.nonblock_run

opos = Openplacos::Client.new

serverxml = XMLRPC::Server.new(options[:port], '0.0.0.0')#, 150, $stderr)

serverxml.add_handler("sensors") do
    opos.sensors.keys
end

serverxml.add_handler("actuators") do
    opos.actuators.keys
end

serverxml.add_handler("actuators.methods") do |path|
    opos.actuators[path].methods.keys
end

serverxml.add_handler("objects") do
    opos.objects.keys
end

serverxml.add_handler("get") do |path|
    opos.sensors[path].value[0]
end

serverxml.add_handler("set") do |path, meth|
    eval "opos.actuators[\"#{path}\"].#{meth}"
end

plugin.opos.on_signal("quit") do
  serverxml.shutdown
end

serverxml.serve




