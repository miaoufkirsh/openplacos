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

require 'Event_handler'

class Globals

  # Print trace when debug env var defined
  def self.trace(string_)
    if ENV['VERBOSE_OPOS'] != nil
      puts string_
    end
  end

  def self.error(string,code = 255)
    puts string
    eh = Event_Handler.instance
    eh.error (string)
    eh.quit()
    Process.exit code
  end
end
