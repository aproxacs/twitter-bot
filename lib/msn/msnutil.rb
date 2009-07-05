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
class Timer
  attr_reader :duration
  
  def initialize(seconds, timeout_event)
    @duration = seconds
    @timeout_event = timeout_event
    @started = Time.now
    @running = false
    @finished = false
    # saving the thread as member far, just to be sure that the GC doesn't kill it
    @thread = Thread.new() do
      while !@finished
        sleep 1
        if (@running)
          if Time.now - @started > @duration
            @timeout_event.call if @timeout_event
            @running = false
          end
        end
      end
    end
  end
  
  def start
    @started = Time.now
    @running = true
  end
  
  def stop
    @running = false
  end
  
  def finish
    @running = false
    @finished = true
  end
end

class MSNStatus
  attr_reader :code
  attr_reader :name
  
  def initialize(code)
    @code = code
    @name = "Unknown"
    case code
    when "NLN"
      @name = "Online"
    when "FLN"
      @name = "Offline"
    when "HDN"
      @name = "Hidden"
    when "BSY"
      @name = "Busy"
    when "AWY"
      @name = "Away"
    when "PHN"
      @name = "On The Phone"
    when "LUN"
      @name = "Out To Lunch"
    when "IDL"
      @name = "Idle"
    when "BRB"
      @name = "Be Right Back"
    end
  end
end

class MSNContact
  attr_reader :email
  attr_accessor :nick
  attr_accessor :status
  
  def initialize(email, nick, status)
    update(email, nick, status)
  end
  
  def update(email, nick, status)
    @email = email
    @nick = nick
    @status = status
  end
end

class MSNContactList
  attr_reader :list
  
  def initialize
    @list = Hash.new
  end
  
  def add_contact(contact)
    @list[contact.email] = contact
  end
  
  def remove_contact(contact)
    @list.delete contact.email
  end
  
  def [](contact)
    return @list[contact]
  end
end

module MSNProtocol
  attr_writer :debuglog
  
  def init_protocol
    @debuglog = lambda { |message| puts message }
    @trid = 1
    @receivebuffer = ""
    @nextpayload = 0
    @lastcommand = ""
    @receiveproc = lambda { |data| process_data data }
  end
  
  def send_command(command)
    @debuglog.call "--> Sent: " + "#{command}\r\n".dump if @debuglog
    @socket.write(command + "\r\n")
    @trid += 1
  end
  
  def process_data(data)
    @receivebuffer << data
    nplc = @nextpayload
    if nplc > 0
      if @receivebuffer.length >= nplc
        parse_data @receivebuffer[0..(nplc-1)]
        @receivebuffer[0..(nplc-1)] = ""
      else
        return
      end
    end
    while (nlpos = @receivebuffer.index("\r\n")) != nil
      parse_data @receivebuffer[0..(nlpos+1)]
      @receivebuffer[0..(nlpos+1)] = ""
      nplc = @nextpayload
      if nplc > 0
        if @receivebuffer.length >= nplc
          parse_data @receivebuffer[0..(nplc-1)]
          @receivebuffer[0..(nplc-1)] = ""
        else
          return
        end
      end
    end
  end
  
  def parse_data(data)
    @debuglog.call "--> Recv: " + data.dump if @debuglog

    if @nextpayload == 0
      handle_command(data)
    else
      handle_payload(@lastcommand, data)
      @nextpayload = 0
    end
  end
end

