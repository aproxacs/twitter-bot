=begin
Copyright (c) 2007 RubyMSN team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
=end
require 'socket'
require 'thread'

class ThreadTCPSocket < Socket
  include Socket::Constants
  
  def initialize(port, host, data_available_event, error_event)
    super(AF_INET, SOCK_STREAM, 0)
    @sockaddr = Socket.sockaddr_in(port, host)

    @data_available_event = data_available_event
    @error_event = error_event
    
    @closed = false
    @data_mutex = Mutex.new
    @closed_mutex = Mutex.new
    
    connect(@sockaddr)
    
    @read_thread = Thread.new(self) do |socket|
      closed = false
      while !closed
        data = recv(1024)
        if data != ""
          @data_available_event.call(data)
        end
        sleep 0.1
        closed = @closed
      end
    end
  end
  
  def close
    @closed = true
    close_read
    @read_thread.join unless Thread.current==@read_thread
  end
end
