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
#

require "rubygems"
require 'active_record' 
require "openplacos"
require "micro-optparse"
require "logger"

options = Parser.new do |p|
  p.banner = "This is openplacos plugins for sql database"
  p.version = "sql 1.0"
  p.option :database, "the name of the database", :default => "openplacos"
  p.option :username, "the name of the user", :default => "openplacos"
  p.option :password, "the password", :default => "opospass"
end.process!(ARGV)


plugin = Openplacos::Plugin.new

options = { "adapter" => "mysql",
            "encoding" => "utf8",
            "database" => options[:database],
            "username" => options[:username],
            "password" => options[:password]}

ActiveRecord::Base.default_timezone = :utc

ActiveRecord::Base.establish_connection( options )
ActiveRecord::Base.logger = Logger.new(STDOUT)

Dir.chdir(  File.expand_path(File.dirname(__FILE__) + "/"))

ActiveRecord::Migrator.migrate('db/migrate')

MUT = Mutex.new

class User < ActiveRecord::Base
  #has_many :flows
end
class Card < ActiveRecord::Base
  #has_many :devices
end
class Device < ActiveRecord::Base 
  #belongs_to :card
  #has_many :sensors
  #has_many :actuators
end
class Sensor < ActiveRecord::Base
  #belongs_to :device
  #has_many :measures
end
class Actuator < ActiveRecord::Base 
  #belongs_to :device
  #has_many :instructions
end
class Flow < ActiveRecord::Base
  #belongs_to :user
  #has_many :measures
  #has_many :instructions
end
class Measure < ActiveRecord::Base
  #belongs_to :flow
  #belongs_to :sensor
end
class Instruction < ActiveRecord::Base
  #belongs_to :flow
  #belongs_to :actuator 
end

plugin.opos.on_signal("create_measure") do |name,config|
  begin
    MUT.synchronize{
      if !Device.exists?(:config_name => config["path"])
        dev = Device.create(:config_name => config["path"],
                            :model => config["model"],
                            :path_dbus => config["path"])
                            #:card_id => Card.find(:first, :conditions => [ "config_name = ?",  meas.instance_variable_get(:@card_name)]))
                            
        Sensor.create(:device_id => dev.id, :unit => config["informations"]['unit'])
      end
    }
  rescue
    puts "Error"
  end
end

plugin.opos.on_signal("create_actuator") do |name,config|
  begin
    MUT.synchronize{
      if !Device.exists?(:config_name => config["path"])
        dev = Device.create(:config_name => config["path"],
                            :model => config["model"],
                            :path_dbus => config["path"])
                            #:card_id => Card.find(:first, :conditions => [ "config_name = ?", act.instance_variable_get(:@card_name)])) 
        Actuator.create(:device_id => dev.id, :interface => config["driver"]["interface"]) 
      end
    }
  rescue
    puts "Error"
  end
end

plugin.opos.on_signal("new_measure") do |name, value, option|
  begin
    MUT.synchronize{    
      time = Time.new.utc  
      flow = Flow.create(:date  => time ,:value => value) 
      device =  Device.find(:first, :conditions => { :config_name => name })
      sensor =  Sensor.find(:first, :conditions => { :device_id => device.id })
      Measure.create(:flow_id => flow.id,:sensor_id => sensor.id) 
    }
  rescue
    puts "Error"
  end
end

plugin.opos.on_signal("new_order") do |name, order, option|
  begin
    MUT.synchronize{
      flow = Flow.create(:date  => Time.new.utc ,:value => order) 
      device =  Device.find(:first, :conditions => { :config_name => name })
      actuator = Actuator.find(:first, :conditions => { :device_id => device.id })
      Instruction.create(:flow_id => flow.id,:actuator_id => actuator.id)
    }
  rescue
    puts "Error"
  end
end

plugin.opos.on_signal("create_card") do |name,config|
  begin
    MUT.synchronize{
      if !Card.exists?(:config_name => name)
        Card.create(:config_name => name, :path_dbus => name ) # model, usb id missing
      end
    }
  rescue
    puts "Error"
  end
end

plugin.run
