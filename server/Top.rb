#/usr/bin/ruby -w

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


# List of local include
require 'Driver_object.rb'
require 'Request.rb'
require 'Measure.rb'

# List of library include
require 'yaml' 

#DBus
sessionBus = DBus::session_bus
service = sessionBus.request_service("org.openplacos.server")

class Top
  attr_reader :measure
  attr_reader :driver

  def initialize (config_, service_)
    # Parse yaml
    @config =  YAML::load(File.read(config_))
    
    @service = service_

    # Config 
    @driver = Hash.new
    @measure = Hash.new

    # Create measure
    @config["measure"].each { |meas|
      @measure.store(meas["name"], Measure.new(meas, self))
    }

    # Check dependencies
    @measure.each_value{ |meas|
      meas.sanity_check()
    }

    # Configure all the driver
    @config["card"].each { |card|

      # Get object list
      object_list = Array.new
      card["object"].each_value{ |obj|
        object_list.push("/" + obj)
      }
      @driver.store(card["name"], Driver_object.new( card["name"], card["driver"], card["interface"], object_list))
      
      # DBus server config
      card["object"].each_pair{ |device, pin|
        exported_obj = Request.new(device, driver[card["name"]].pins["/"+pin])
        @service.export(exported_obj)
      }
    }

  end
end

if (ARGV[0] == nil)
  puts "Please specify a config file"
  puts "Usage: openplacos-server <config-file>"
  Process.exit
end

if (! File.exist?(ARGV[0]))
  puts "Config file " +ARGV[0]+" doesn't exist"
  Process.exit
end


if (! File.readable?(ARGV[0]))
  puts "Config file " +ARGV[0]+" not readable"
  Process.exit
end


top = Top.new(ARGV[0], service)

main = DBus::Main.new
main << sessionBus
main.run

