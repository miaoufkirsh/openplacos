class Room
    
    attr_accessor :path, :sensors, :actuators, :backend, :connect
    
    def initialize(connection, path)
      @connect = connection
      if not path=="/"
        @path = path + "/" 
      else
        @path = path
      end
      
      @backend = connection.rooms[@path]

      @sensors = Hash.new
      @actuators = Hash.new
      puts @backend.objects.keys
      @backend.objects.each_pair{ |key, value|
        if value.has_iface? 'org.openplacos.server.measure'
          @sensors.store(value,  Sensor.new(@connect,key))
        elsif value.has_iface? 'org.openplacos.server.actuator'
          @actuators.store(value,  Actuator.new(@connect,key))
        end
      }

    end

    def name
        if @path == "/"
            return "OpenplacOS"
        else
            return @path
        end
    end

end
