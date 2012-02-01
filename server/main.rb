#!/usr/bin/ruby

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
#

$INSTALL_PATH = File.dirname(__FILE__) + "/"
$LOAD_PATH << $INSTALL_PATH
$INSTALL_PATH = '/usr/lib/ruby/openplacos/server/'
$LOAD_PATH << $INSTALL_PATH 
ENV["DBUS_THREADED_ACCESS"] = "1" #activate threaded dbus


# List of library include
require 'json'
require 'yaml' 
require 'rubygems'
require 'dbus-openplacos'
require 'micro-optparse'
require 'thin'
require 'sinatra/base'

# List of local include
require 'globals.rb'
require 'User.rb'
require 'Component.rb'
require 'Event_handler.rb'
require 'Dispatcher.rb'
require 'Export.rb'
require 'Info.rb'
require 'WebServer.rb'

options = Parser.new do |p|
  p.banner = "The openplacos server"
  p.version = "0.0.1"
  p.option :file   , "the config file", :default => "/etc/default/openplacos"
  p.option :debug  , "activate the ruby-dbus debug flag"
  p.option :session, "client bus on user session bus"
  p.option :port, "port of the webserver", :default => 4567
end.process!

$DEBUG = options[:debug]

if options[:session]
  ENV['DEBUG_OPOS'] = "1"
end

#DBus
if(ENV['DEBUG_OPOS'] ) ## Stand for debug
  Bus = DBus::SessionBus.instance
  $INSTALL_PATH = File.dirname(__FILE__) + "/"
else
  Bus = DBus::SystemBus.instance
end
InternalBus = DBus::ASessionBus.new

service = Bus.request_service("org.openplacos.server")
internalservice = InternalBus.request_service("org.openplacos.server.internal")
internalservice.threaded = true

class Top

  attr_reader :components, :exports
  
  #1 Config file path
  #2 Dbus session reference
  def initialize (config_, service_, internalservice_)
    # Parse yaml
    @config           =  YAML::load(File.read(config_))
    @service          = service_
    @internalservice  = internalservice_
    @config_component = @config["component"]
    @config_export    = @config["export"]


    # Event_handler creation
    @event_handler = Event_Handler.instance
    @internalservice.export(@event_handler)

    Pathfinder.instance.init_pathfinder(@config["pathfinder"])

    @info = Info.new()
    @service.export(@info)

    # Hash of available dbus objects (measures, actuators..)
    # the hash key is the dbus path
    @components = Array.new
    @exports    = Array.new

  end

  def inspect_components
    @config_component.each do |component|
      @components << Component.new(component) # Create a component object
    end 
    
    # introspect phase
    @components.each  do |component|
      component.introspect   # Get informations from component -- threaded
    end

    # analyse phase => creation of Pins
    @components.each  do |component|
      component.analyse   # Create pin objects according to introspect
    end
  end

  def  create_exported_object
    @config_export.each do |export|
      @exports << Export.new(export)
    end
  end

  def export
     @exports.each do |export|
      export.pin_output.expose_on_dbus()
      export.expose_on_web()
      @service.export(export.pin_output)
    end   
  end

  def map
   disp =  Dispatcher.instance
    @config["mapping"].each do |wire|
      disp.add_wire(wire) # Push every wire link into dispatcher
    end
  end

  def expose_component
  @components.each  do |component|
      component.expose()   # Exposes on dbus interface service
      component.outputs.each do |p|
        @internalservice.export(p)
      end
    end
  end

  def launch_components
    @components.each  do |component|
      component.launch # Launch every component -- threaded
    end

    @components.each  do |component|
       component.wait_for # verify component has been launched 
    end
  end
  
  def quit
    @event_handler.quit
  end
  
end # End of Top

def quit(top_, internalmain_, main_)
  top_.quit
  internalmain_.quit
  main_.quit
end

# Config file basic verification
file = options[:file]

if (! File.exist?(file))
  Globals.error("Config file #{file} doesn't exist",1)
end


if (! File.readable?(file))
  Globals.error("Config file #{file} not readable")
end

# Where am I ?
if File.symlink?(__FILE__)
  PATH =  File.dirname(File.readlink(__FILE__))
else 
  PATH = File.expand_path(File.dirname(__FILE__))
end

Dispatcher.instance.init_dispatcher 

# Construct Top
top = Top.new(file, service, internalservice)
top.map
top.inspect_components
top.expose_component
top.create_exported_object
Dispatcher.instance.check_all_pin
top.export

internalmain = DBus::Main.new
internalmain << InternalBus
Thread.new { internalmain.run }

#launch components
top.launch_components

# create the webserver
server = ThinServer.new('0.0.0.0', options[:port])

# start the WebServer
# Threaded server should be removed when main dbus will be removed

Thread.new{
  server.start!
}

# Let's Dbus have execution control
main = DBus::Main.new
main << Bus

# quit the plugins when server quit
Signal.trap('TERM') do 
  server.stop!
  quit(top, internalmain, main)
end

Signal.trap('INT') do 
  server.stop!
  quit(top, internalmain, main)
end

main.run

top.components.each { |c|
  if !c.thread.nil?
    c.thread.join
  end
}

