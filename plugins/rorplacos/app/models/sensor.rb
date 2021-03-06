class Sensor < ActiveRecord::Base
    belongs_to :device
    has_many :measures
    has_many :flows , :through => :measures
    
    attr_reader :path, :backend, :config, :unit

    def initialize(connection, path)
      @connect = connection
      @path = path
      @backend = connection.sensors[@path]
      @config = connection.objects[@path]['org.openplacos.server.config'].getConfig[0]
      @unit = @config["informations"]["unit"] || " "
    end
  
    def value
      val = @backend.value[0]
      if val.is_a?(Float)
        val = val.round(2)
      end
      return val.to_s + " " + @unit
    end
    
    
    def regul_status
      status = "NA"
      if (@connect.is_regul(@backend))
        if (@connect.get_regul_iface(@backend).state[0] )
          status = "ON"
        else 
          status = "OFF"
        end
      end
      return status
    end
    
    def generate_graph(start_date,end_date)
      meas = Device.find(:first, :conditions => {:config_name => @path}).sensor.flows.where("date >= :start_date and date <= :end_date",{:start_date => start_date, :end_date => end_date}).order("date DESC")
      
      slice_size = [meas.size/500,1].max.to_i
      
      ret = [];
      
      meas.each_slice(slice_size) { |m| ret.push([m[0].date.to_i*1000, m[0].value]) }
    
      return ret
    end
end
