#!/usr/bin/ruby
#
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

require 'dbus-openplacos'
require 'rubygems'
require 'phidgets'
require 'yaml'


class IfkDigitalInput < DBus::Object

	def initialize(phidget, path, index)
	    super(path)
	    @phidget = phidget
		@index = index
		@trigger = 1
	end

    dbus_interface "org.openplacos.driver.digital" do

		dbus_method :read, "out return:v, in option:a{sv}" do |option|
			self.read
		end  
		
		dbus_method :write, "out return:v, in value:v, in option:a{sv}" do |value, option|
		    self.write value
		end
	end
	
	dbus_interface "org.openplacos.driver.signal" do
	    dbus_signal :change, "value:i" do
	        self.read
	    end
    end

    def read
        begin
            @phidget.synchronize do
                @phidget.getInputState(@index)
            end
		rescue Phidgets::Exception => e
		    puts "Phidgets Error (#{e.code}). #{e}"
		    return -1
        end
    end
	
	def write(value)
	    puts "IfkDigitalInput : write not supported"
	    return -1
    end
	
end # class


class IfkDigitalOutput < DBus::Object

	def initialize(phidget, path, index)
	    super(path)
	    @phidget = phidget
		@index = index
	end

    dbus_interface "org.openplacos.driver.digital" do

		dbus_method :read, "out return:v, in option:a{sv}" do |option|
            self.read
		end
		
		dbus_method :write, "out return:v, in value:v, in option:a{sv}" do |value, option|
            self.write value
		end
	end
	
	def read
	    begin
            @phidget.synchronize do
                @phidget.getOutputState(@index)
            end
		rescue Phidgets::Exception => e
		    puts "Phidgets Error (#{e.code}). #{e}"
		    return -1
	    end
	end
	
	def write(value)
	    begin
	        @phidget.synchronize do
	            if value then v = 1 else v = 0 end
			    @phidget.setOutputState(@index, v)
		    end
		rescue Phidgets::Exception => e
		    puts "Phidgets Error (#{e.code}). #{e}"
		    return -1
	    end
	    return 0
	end
	
end # class


class IfkAnalogInput < DBus::Object

	def initialize(phidget, path, index)
	    super(path)
	    @phidget = phidget
		@index = index
		@trigger = 2
	end

    dbus_interface "org.openplacos.driver.analog" do

		dbus_method :read, "out return:v, in option:a{sv}" do |option|
			self.read
		end
		
		dbus_method :write, "out return:v, in value:v, in option:a{sv}" do |value, option|
            self.write value
		end
	end
		
	dbus_interface "org.openplacos.driver.signal" do
	    dbus_signal :change, "value:i"
    end
    
	def read
        begin
            @phidget.synchronize do
    			value = @phidget.getSensorValue(@index)
			end
		rescue Phidgets::Exception => e
		    puts "Phidgets Error (#{e.code}). #{e}"
		    return -1
        end
	end

    def write(value)
        puts "IfkAnalogInput : write not supported"
	    return -1
    end	
	
end # class

# Redefine Phidgets::InterfaceKit to add mutex capabilities
class Phidgets::InterfaceKit

    def synchronize
        @mutex ||= Mutex.new
        @mutex.synchronize do
            yield
        end
    end
end # class

#
# Live
#
if __FILE__ == $0

    if not ARGV[0]
        puts "Usage : #{$0} address"
        exit(1)
    end

    # config
    PollingTime = 0.1
    address = ARGV[0].to_i
    
    # flags
    the_end = false

    # Bus Open and Service Name Request
    bus = DBus::system_bus
    if(ENV['DEBUG_OPOS'] ) ## Stand for debug
      bus =  DBus::session_bus
    end
    dbus_service = bus.request_service("org.openplacos.drivers.interfacekit-#{address}")
    
    begin
        phidget = Phidgets::InterfaceKit.new(address,2000)
    rescue Phidgets::Exception => e
        puts "Phidgets Error (#{e.code}). #{e}"
        exit(-1)
    end

    pins = Array.new
    watched_pins = Array.new   # pins to monitor
    phidget.getOutputCount.times do |i|
        path = "/digital/output/#{i}"
        pins << IfkDigitalOutput.new(phidget, path, i)
    end
    phidget.getInputCount.times do |i|
        path = "/digital/input/#{i}"
        pins << IfkDigitalInput.new(phidget, path, i)
        #watched_pins << pins.last
    end
    phidget.getSensorCount.times do |i|
        path = "/analog/input/#{i}"
        pins << IfkAnalogInput.new(phidget, path, i)
        #watched_pins << pins.last
    end
    pins.each do |pin|
       dbus_service.export(pin)
       puts pin.path
    end


    Poll = true
    if Poll 
        # Polling thread
        thrd_poll = Thread.new do
            old = []
            watched_pins.each do |pin|
                old << pin.read
            end
            until the_end
                new = []
                watched_pins.each do |pin|
                    new << pin.read
                    sleep 0.01
                end
                if new != old
                    new.each_index do |i|
                        # emit dbus signal if difference between old and new value is more than the defined trigger
                        if (new[i] - old[i]).abs >= watched_pins[i].trigger
                            watched_pins[i].change(new[i])
                            old[i] = new[i]
                        end
                    end
                end
                sleep PollingTime
            end
        end
    end

    puts "listening"
    main = DBus::Main.new
    main << bus
    main.run
    
    the_end = true
    thrd_poll.join
    
end
