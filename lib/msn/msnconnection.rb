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
require 'digest/md5'
require 'net/https'
require 'msn/threadsocket'
require 'cgi'

class MSNConnection
  include MSNProtocol
  
  attr_reader :email
  attr_reader :contactlists
  attr_reader :chatsessions
  attr_reader :is_signed_in
  attr_reader :commandhandlers
  attr_reader :terminated
  attr_reader :status
  attr_reader :nickname
  
  attr_writer :signed_in
  attr_writer :buddy_update
  attr_writer :new_chat_session
  attr_writer :new_contact
  attr_writer :request_initial_status
  
  def initialize(email, password)
    # events
    @signed_in = nil
    @buddy_update = nil
    @new_chat_session = nil
    
    # default handlers
    @new_contact = lambda { |newemail|
      add_contact("AL", newemail)
      add_contact("FL", newemail)
    }
    @request_initial_status = lambda { return MSNStatus.new("NLN") }
    
    # initialization
    @contactlists = Hash.new
    @contactlists["FL"] = MSNContactList.new
    @contactlists["AL"] = MSNContactList.new
    @contactlists["BL"] = MSNContactList.new
    @contactlists["RL"] = MSNContactList.new
    @chatsessions = Hash.new
    @email = email
    @password = password
    @initial_add_allow_queue = []
    @pngtimer = Timer.new(60, lambda { send_ping })
    @is_signed_in = false
    @tag_counter = 0
    @commandhandlers = Hash.new
    @status = MSNStatus.new('FLN')
    @nickname = ''
    # flags
    @terminated = false
    
    connect_commandhandlers
    
    init_protocol
    @version_message = "VER #{@trid} MSNP9 CVR0"
  end
  
  def start
    @socket = ThreadTCPSocket.new(1863, "messenger.hotmail.com", @receiveproc, nil)
    send_command @version_message
  end
  
  def send_ping
    if @is_signed_in
      send_command "PNG"
      @pngtimer.start
    end
  end
  
  def get_tag_counter
    @tag_counter += 1
    return @tag_counter
  end
  
  def connect_commandhandlers
    # each commandhandler can be overridden with custom handlers to provide maximum flexibility
    
    @commandhandlers["VER"] = lambda { |cp| handle_ver }
    @commandhandlers["CVR"] = lambda { |cp| handle_cvr }
    @commandhandlers["XFR"] = lambda { |cp| handle_xfr cp }
    @commandhandlers["USR"] = lambda { |cp| handle_usr cp }
    @commandhandlers["SYN"] = lambda { |cp| handle_syn }
    @commandhandlers["CHG"] = lambda { |cp| handle_chg cp }
    @commandhandlers["CHL"] = lambda { |cp| handle_chl cp }
    @commandhandlers["ADD"] = lambda { |cp| handle_add cp }
    @commandhandlers["REM"] = lambda { |cp| handle_rem cp }
    @commandhandlers["LST"] = lambda { |cp| handle_lst cp }
    @commandhandlers["ILN"] = lambda { |cp| handle_iln cp }
    @commandhandlers["NLN"] = lambda { |cp| handle_nln cp }
    @commandhandlers["FLN"] = lambda { |cp| handle_fln cp }
    @commandhandlers["RNG"] = lambda { |cp| handle_rng cp }
    @commandhandlers["OUT"] = lambda { |cp| handle_out cp }
    @commandhandlers["REA"] = lambda { |cp| handle_rea cp }
  end
  
  def handle_ver
    send_command "CVR #{@trid} 0x0409 winnt 5.1 i386 MSNMSGR 5.0.0540 MSMSGS #{@email}"
  end
  
  def handle_cvr
    send_command "USR #{@trid} TWN I #{@email}"
  end
  
  def handle_xfr(cp)
    if cp[2] == "NS"
      @socket = ThreadTCPSocket.new(cp[3].split(":")[1].to_i, cp[3].split(":")[0], @receiveproc, nil)
      @trid = 1
      send_command @version_message
    elsif cp[2] == "SB"
      sb_server = cp[3]
      sb_code = cp[5]
      newsession = MSNChatSession.new(@email, @chat_request_contact, sb_server.split(":")[0], sb_server.split(":")[1].to_i, sb_code, true, @contactlists["FL"])
      newsession.tag = @chat_request_tag
      newsession.connection = self
      @chatsessions[@chat_request_tag] = newsession
      @new_chat_session.call(@chat_request_tag, newsession) if @new_chat_session
    end
  end
  
  def handle_usr(cp)
    if cp[2] == "OK"
      send_command "SYN #{@trid} 0"
      @nickname = CGI.unescape(cp[4])
    else
      authenticate_with_ssl cp[4]
    end
  end
  
  def handle_syn
    initialstatus = @request_initial_status.call if @request_initial_status
    send_command "CHG #{@trid} #{initialstatus.code}"
  end
  
  def handle_chg(cp)
    @status = MSNStatus.new(cp[2])
    if !@is_signed_in
      # we are now signed in ;-)
      
      # handle the new buddy event for each new buddy
      @initial_add_allow_queue.each {|contact|
        @new_contact.call contact.email if @new_contact
      }
      @pngtimer.start
      @is_signed_in = true
      @signed_in.call if @signed_in
    end
  end
  
  def handle_chl(cp)
    send_command "QRY #{@trid} msmsgs@msnmsgr.com 32"
    @socket.write(Digest::MD5.hexdigest(cp[2] + "Q1P7W2E4J9R8U3S5"))
  end
  
  def handle_add(cp)
    contact = MSNContact.new(cp[4], cp[5], MSNStatus.new("FLN"))
    @contactlists[cp[2]].add_contact(contact)
    if cp[2] == "RL"
      unless @contactlists["AL"][cp[4]]
        @new_contact.call cp[4] if @new_contact
      end
    end
  end
  
  def handle_rem(cp)
    contact = @contactlists[cp[2]][cp[4]]
    if contact
      @contactlists[cp[2]].remove_contact contact
    end
  end
  
  def handle_lst(cp)
    contact = MSNContact.new(cp[1], cp[2], MSNStatus.new("FLN"))
    listcode = cp[3].to_i
    @contactlists["FL"].add_contact(contact) if listcode & 1 != 0
    @contactlists["AL"].add_contact(contact) if listcode & 2 != 0
    @contactlists["BL"].add_contact(contact) if listcode & 4 != 0
    @contactlists["RL"].add_contact(contact) if listcode & 8 != 0
    if listcode == 8
      # this buddy should be added when signed in!
      @initial_add_allow_queue << contact
    end
  end
  
  def handle_iln(cp)
    peer_email = cp[3]
    status_code = cp[2]
    peer_nick = cp[4]
    contact = @contactlists["FL"][peer_email]
    if contact
      contact.update(peer_email, peer_nick, MSNStatus.new(status_code))
    end
  end
  
  def handle_nln(cp)
    peer_email = cp[2]
    peer_nick = cp[3]
    peer_status = cp[1]
    contact = @contactlists["FL"][peer_email]
    if contact
      oldcontact = MSNContact.new(contact.email, contact.nick, MSNStatus.new(contact.status.code))
      contact.update(peer_email, peer_nick, MSNStatus.new(peer_status))
      @buddy_update.call(oldcontact, contact) if @buddy_update
    end
  end
  
  def handle_fln(cp)
    peer_email = cp[1]
    contact = @contactlists["FL"][peer_email]
    if contact
      oldcontact = MSNContact.new(contact.email, contact.nick, MSNStatus.new(contact.status.code))
      contact.update(peer_email, contact.nick, MSNStatus.new("FLN"))
      @buddy_update.call(oldcontact, contact) if @buddy_update
    end
  end
  
  def handle_rng(cp)
    session = MSNChatSession.new(@email, cp[5], cp[2].split(":")[0], cp[2].split(":")[1].to_i, cp[4], false, @contactlists["FL"])
    session.extracode = cp[1]
    session.connection = self
    session.tag = session.initial_contact.split("@")[0] + get_tag_counter.to_s
    @chatsessions[session.tag] = session
    @new_chat_session.call(session.tag, session) if @new_chat_session
  end
  
  def handle_out(cp)
      @socket.close
      @terminated = true
  end
  
  def handle_rea(cp)
    @nickname = CGI.unescape(cp[4])
  end
  
  def handle_command(command)
    @lastcommand = command
    @pngtimer.start
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
  
  def handle_payload(command, payload)
    newcmd = command[0..command.length-3] # strip crlf
    cp = newcmd.split(" ")
    return if cp.length == 0
    case cp[0]
    when "MSG"
      
    when "NOT"
      
    end
  end
  
  def start_chat(tag, email)
    if email
      @chat_request_contact = email
      @chat_request_tag = tag
      send_command "XFR #{@trid} SB"
    end
  end

  def remove_session(tag)
    @chatsessions.delete(tag)
  end
  
  def add_contact(listcode, email)
    send_command "ADD #{@trid} #{listcode} #{email} #{email}"
  end
  
  def remove_contact(listcode, email)
    send_command "REM #{@trid} #{listcode} #{email}"
  end

  def change_nickname(newnick)
    # send_command "REA #{@trid} #{@email} #{newnick.gsub(/\s/, "%20")}"
    send_command "REA #{@trid} #{@email} #{CGI.escape(newnick).gsub(/\+/, '%20')}"
  end
  
  def change_status(newstatus)
    send_command "CHG #{@trid} #{newstatus.code}"
  end
  
  def close
    send_command "CHG #{@trid} FLN"
    @status = MSNStatus.new('FLN')
    @socket.close
    @terminated = true
  end
  
  def authenticate_with_ssl(cookies)
    # determine loginserver
    server = "login.passport.com"
    if @email.index("@hotmail.com")
      server = "loginnet.passport.com"
    elsif @email.index("@msn.com")
      server = "msnialogin.passport.com"
    end

    headers = {
      "Authorization" => "Passport1.4 OrgVerb=GET,OrgURL=http%3A%2F%2Fmessenger%2Emsn%2Ecom,sign-in=#{@email},pwd=#{@password},#{cookies}",
      "User-Agent" => "MSMSGS",
      "Host" => "login.passport.com",
      "Connection" => "Keep-Alive",
      "Cache-Control" => "no-cache"
    }
    Net::HTTP.version_1_1
    http = Net::HTTP.new(server, 443)
    http.use_ssl = true
    response = nil
    http.start do |http|
      response = http.request_get("/login2.srf", headers)
      response.value
    end
    data = response["Authentication-Info"]
    
    if data.index("from-PP='") 
      cookies = data.split("'")[1]
      # print "--> Cookies received! #{cookies}\n"
      send_command "USR #{@trid} TWN S #{cookies}"
    else
      # wrong password!
    end
  end
end
