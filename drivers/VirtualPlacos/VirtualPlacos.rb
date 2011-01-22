#!/usr/bin/env ruby

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
#
#    Virtual placos for tests

require 'rubygems'
require 'dbus'
require 'thread'
require 'yaml' # Assumed in future examples
require 'pathname'

Thread.abort_on_exception = true

# Virtual placos class
class Virtualplacos 

    attr_accessor :inTemp, :eclairage, :ventilation, :outTemp, :outHygro, :inHygro, :inHygroSensor, :outHygroSensor

    def initialize(outTemp,maxInTemp,outHygro,constEclairage,constVentilation,th_refresh_rate)
        
        @outTemp = outTemp
        @maxInTemp = maxInTemp
        @inTemp = @outTemp
        
        @outHygro = outHygro
        @inHygro = outHygro
        
        @inHygroSensor = @inHygro + 0.1*@inTemp
        @outHygroSensor = @outHygro + 0.1*@outTemp
        
        @eclairage = false
        @ventilation = false
        @th_refresh_rate = th_refresh_rate
        
        @ConstEclairage = constEclairage
        @ConstVentilation = constVentilation
        
        @ventilation_thread = Thread.new{
            loop do
                sleep(@th_refresh_rate)
                if @ventilation == true
                    @inTemp = @inTemp + (@outTemp - @inTemp)*(@th_refresh_rate/@ConstVentilation) # 1 order system
                    @inHygro = @inHygro + (@outHygro - @inHygro)*(@th_refresh_rate/@ConstVentilation) # 1 order system
                    @inHygroSensor = @inHygro + 0.1*@inTemp
                end                 
            end
        }
        
        
        @eclairage_thread = Thread.new{
            loop do
                sleep(@th_refresh_rate)
                if @eclairage == true
                    @inTemp = @inTemp + (@maxInTemp - @inTemp)*(@th_refresh_rate/@ConstEclairage) # 1 order system
                    @inHygro = @inHygro + (95 - @inHygro)*(@th_refresh_rate/@ConstEclairage) # 1 order system
                    @inHygroSensor = @inHygro + 0.1*@inTemp
                end
            end
        }
    
    end

    def setVentilation(state)
        if state == true
            @ventilation = true
            my_notify("Allumage de la ventillation")        
        else
            if state == false
                @ventilation = false
                my_notify("Extinction de la ventillation")      
            end
        end
    end
    
    def setEclairage(state)
        if state == true
            @eclairage = true
            my_notify("Allumage de l'eclairage")
        else
            if state == false
                @eclairage = false
                my_notify("Extinction de l'eclairage")
            end
        end
    end
    
    def dummy(state)
        puts("This is a dummy method")
    end

end

#sensor object

class Sensor < DBus::Object
        
    def initialize(dbusName,variable)
        super(dbusName)
        @variable = variable
    end
    
    dbus_interface "org.openplacos.driver.analog" do
    
        dbus_method :read, "out return:v, in option:a{sv}" do |option|
            return $placos.instance_variable_get("@"+@variable)
        end  
        
    end
    
    dbus_interface "org.openplacos.driver.digital" do

        dbus_method :read, "out return:v, in option:a{sv}" do |option|
            return $placos.instance_variable_get("@"+@variable)
        end  
    end 
end

#actuator object

class Actuator < DBus::Object
        
    def initialize(dbusName,method)
        super(dbusName)
        @method = method
    end
    
    dbus_interface "org.openplacos.driver.analog" do
    
        dbus_method :write, "out return:v, in value:v, in option:a{sv}" do |value, option|
            $placos.method(@method).call value
            return "-1"
        end 
    
    end
    
    dbus_interface "org.openplacos.driver.digital" do

        dbus_method :write, "out return:v, in value:v, in option:a{sv}" do |value, option|
            if (value.class==TrueClass) or (value.class==FalseClass)
                $placos.method(@method).call value
                return true
            else
                if (value==1)
                    $placos.method(@method).call true
                    return true             
                end
                if (value==0)
                    $placos.method(@method).call false
                    return true             
                end
                return false                
            end
        end 
            
    end 
end


# Pin object,

class Pin 
        
    def initialize(service,name,config_device)
        
        if config_device["kind"]=="sensor"
            @device = Sensor.new(name, config_device["VPvariable"])
        else
            if config_device["kind"]=="actuator"
                @device = Actuator.new(name,config_device["VPmethod"])
            end
        end
        
        service.export(@device)
        
    end

end

class DebugState < DBus::Object

    
    dbus_interface "org.openplacos.driver.debug" do
    
        dbus_method :GetState, "out option:a{sv}" do |option|
          var = $placos.instance_variables
          ret = Hash.new
          var.each { |v|
            
            val = $placos.instance_variable_get(v)
            if val.kind_of?(String) or val.kind_of?(Float) or val.kind_of?(Fixnum) or val.kind_of?(TrueClass) or val.kind_of?(FalseClass)
            ret[v] = val
            end
          }
          [ret]           
        end  
        
    end

end

class Interupt < DBus::Object
        
    def initialize(variable,threshold)
        @variable = variable
        @threshold = threshold
        @state = false
        
        # Start pulling thread
        Thread.new{
            loop do
                sleep(0.1)
                
                if @state == false
                
                    if $placos.instance_variable_get("@"+@variable) > @threshold
                        #self.Signal(true)
                        @state = true
                    end
                
                elsif @state == true
                
                    if $placos.instance_variable_get("@"+@variable) < @threshold
                        #self.Signal(false)
                        @state = false
                    end
                
                end
            end
        }
        
    end

end

def my_notify(message)
    if $notify==true 
        $notifyIface.Notify('VirtualPlacos', 0,Pathname.pwd.to_s + "/icones/VirtualPlacos.png","VirtualPlacos",message,[], {}, -1)
    end
    puts message
end

if (ARGV[0] == nil)
 ARGV[0] = File.dirname(__FILE__) + '/config.yaml'
end

if (! File.exist?(ARGV[0]))
  puts "Config file " +ARGV[0]+" doesn't exist"
  Process.exit
end


if (! File.readable?(ARGV[0]))
  puts "Config file " +ARGV[0]+" not readable"
  Process.exit
end


#Load and parse config file
config =  YAML::load(File.read(ARGV[0]))

config_placos = config['placos']


#create placos
$placos = Virtualplacos.new(config_placos["Outdoor Temperature"].to_f,config_placos["Max Indoor Temperature"].to_f,config_placos["Outdoor Hygro"].to_f,config_placos["Light Time Constant"].to_f,config_placos["Ventillation Time Constant"].to_f,config_placos["Thread Refresh Rate"].to_f)


bus = DBus.system_bus
if(ENV['DEBUG_OPOS'] ) ## Stand for debug
  bus =  DBus.session_bus
end

# #check notification system
# $notify = config['allow notify']

# # Start notification systeme
# if $notify==true
#     notifyService = bus.service("org.freedesktop.Notifications")
#     notifyObject = notifyService.object('/org/freedesktop/Notifications')
#     notifyObject.introspect
#     $notifyIface = notifyObject['org.freedesktop.Notifications']
# end

#publish methods on dbus

service = bus.request_service("org.openplacos.drivers.virtualplacos")

#create pin objects
config_pins = config['pins']
config_devices = config['devices']


$pin = Hash.new

config_pins.each_pair { |pin_name , device_name|
    puts "create " + pin_name + " with config : " + config_devices[device_name].inspect
    $pin[pin_name] = Pin.new(service,pin_name,config_devices[device_name])
}
debug = DebugState.new("Debug")
service.export(debug)

main = DBus::Main.new
main << bus
main.run


