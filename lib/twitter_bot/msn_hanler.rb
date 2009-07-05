module TwitterBot
  class MsnHandler
    def initialize(options = {})
      @options = options
      self
    end

    def start
      TwitterBot.info "== Starting Twitter Bot =="
      create_conn do |conn|
        conn.new_chat_session = lambda do |tag, session|
          TwitterBot.info "=> new chat session created with tag '#{tag}'!"
          #        session.debuglog =  nil

          session.message_received = lambda do |sender, message|
            TwitterBot.info "=> #{sender} says: #{message}"
            begin
              worker.handle_message(session, sender, message)
            rescue Exception => e
              TwitterBot.error e.backtrace.join("\n")
              TwitterBot.error e
            end
          end
          session.session_started = lambda do
            TwitterBot.debug "=> Session started : #{tag}"
            return unless worker.has_user? tag
            
            TwitterBot.debug "=> #{tag} : has #{worker.msg_queue_of(tag).size} messages"
            worker.msg_queue_of(tag).each do |msg|
              TwitterBot.info "=> Send msg to #{tag} : #{msg}"
              session.say msg
            end
            worker.msg_queue_of(tag).clear
            TwitterBot.debug "=> Close session : #{tag}"
            session.close
          end

          session.start
        end
      end.start
      
      keep_alive
    end

    protected
    
    def worker
      @worker ||= Worker.new(@conn, @options)
    end

    def create_conn
      msn = @options[:msn]
      @conn = MSNConnection.new(msn[:id], msn[:password])
      @conn.signed_in = lambda {
        @conn.change_nickname "Twitter Bot"
      }
      #      @conn.debuglog = nil
      yield @conn if block_given?
      @conn
    end

    def keep_alive
      interval = @options[:interval].to_i
      EventMachine::run do
        EventMachine::add_periodic_timer(interval) do
          @conn.send_ping
          begin
            worker.check_twitter
          rescue Exception => e
            TwitterBot.error e.backtrace.join("\n")
            TwitterBot.error e
          end
        end
      end
    end
  end
end