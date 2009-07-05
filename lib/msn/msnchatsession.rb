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
require 'msn/msnutil'

class MSNChatSession
  include MSNProtocol
  
  attr_writer :extracode
  attr_reader :is_inviting
  attr_reader :initial_contact
  attr_reader :participants
  attr_reader :commandhandlers
  attr_writer :message_received
  attr_writer :session_started
  attr_writer :session_ended
  attr_writer :participants_updated

  attr_accessor :tag
  attr_accessor :connection
  
  def initialize(self_email, initial_contact, server, port, code, is_inviting, contactlist)
    #events
    @message_received = nil
    @session_started = nil
    @session_ended = nil
    @participants_updated = nil
    
    # properties
    @contactlist = contactlist
    @participants = MSNContactList.new
    @extracode = nil
    @code = code
    @initial_contact = initial_contact
    @self_email = self_email
    @commandhandlers = Hash.new
    connect_commandhandlers
    
    init_protocol
    @is_inviting = is_inviting
    @socket = ThreadTCPSocket.new(port, server, @receiveproc, nil)
  end

  def email
    @self_email
  end
  
  def start
    if @is_inviting
      send_command "USR #{@trid} #{@self_email} #{@code}"
    else
      send_command "ANS #{@trid} #{@self_email} #{@code} #{@extracode}"
    end
  end

  def close
    @session_ended.call if @session_ended
    send_command "OUT"
    connection.remove_session(@tag)
    @socket.close
  end
  
  def connect_commandhandlers
    @commandhandlers["USR"] = lambda { |cp| handle_usr cp }
    @commandhandlers["CAL"] = lambda { |cp| handle_cal cp }
    @commandhandlers["JOI"] = lambda { |cp| handle_joi cp }
    @commandhandlers["ANS"] = lambda { |cp| handle_ans cp }
    @commandhandlers["IRO"] = lambda { |cp| handle_iro cp }
    @commandhandlers["BYE"] = lambda { |cp| handle_bye cp }
  end
  
  def handle_usr(cp)
    if cp[2] == "OK"
      send_command "CAL #{@trid} #{@initial_contact}"
    end
  end
  
  def handle_cal(cp)
    if cp[2] == "RINGING"
    end
  end
  
  def handle_joi(cp)
    peer_email = cp[1]
    peer_nick = cp[2]
    puts "#{peer_email} joined the chat session!"
    contact = @contactlist[peer_email]
    @participants.add_contact contact if contact
    @participants.add_contact MSNContact.new(peer_email, peer_nick, MSNStatus.new("FLN")) unless contact
    @participants_updated.call if @participants_updated
    @session_started.call if @session_started && @participants.list.length == 1
  end
  
  def handle_ans(cp)
    @session_started.call if @session_started
  end
  
  def handle_iro(cp)
    contact = @contactlist[cp[4]]
    @participants.add_contact contact if contact
    @participants.add_contact MSNContact.new(cp[4], cp[5], MSNStatus.new("FLN")) unless contact
    @participants_updated.call if @participants_updated
  end
  
  def handle_bye(cp)
    @participants.remove_contact @participants[cp[1]]
    
    @participants_updated.call if @participants_updated && @participants.list.length > 0
    close if @particpants.list.length == 0
  end
  
  def handle_command(command)
    @lastcommand = command
    newcmd = command[0..command.length-3] # strip crlf
    cp = newcmd.split(" ")
    return if cp.length == 0
    handler = @commandhandlers[cp[0]]
    handler.call cp if handler
    case cp[0]
    when "NOT"
      @nextpayload = cp[1].to_i
    when "MSG"
      @nextpayload = cp[3].to_i
    end
  end
  
  def say(message)
    mimestring = "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nX-MMS-IM-Format: FN=Arial; EF=; CO=0; CS=0; PF=22\r\n\r\n#{message}"
    send_command "MSG #{@trid} A #{mimestring.length.to_s}"
    @socket.write mimestring
  end
  
  def handle_payload(command, payload)
    newcmd = command[0..command.length-3] # strip crlf
    cp = newcmd.split(" ")
    if cp.length == 0
      return
    end
    case cp[0]
    when "MSG"
      peer_email = cp[1]
      if payload.index("Content-Type: text/plain")
        message = payload[payload.index("\r\n\r\n") + 4..payload.length-1]
        @message_received.call(peer_email, message) if @message_received
      end
    when "NOT"
      
    end
  end
end
