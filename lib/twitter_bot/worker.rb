module TwitterBot
  class Worker
    def initialize(conn, options)
      @conn = conn
      @options = options
      @msg_queue = {}
      load_users
    end

    def handle_message(session, sender, message)
      user = find_user(sender)
      case message
      when /^!oauth/
        session.say """ \
Please connect to #{user.request_token.authorize_url} and complete the authentication. \
After completing authentication, twitter will show you 6 digit numbers. This is a PIN code.
Please let me know these 6 digit PIN code with !pin command.

EXAMPLE : !pin 432433
        """

      when /^!pin/
        message =~ /^!pin\s+(\d{6})/
        digits = $1
        user.complete_oauth(digits)
        if user.authorized?
          save_users
          msg = "Good! Success to sign in Twitter! Have fun with me!"
        else
          msg = "Sorry. Fail to sign in Twitter. Maybe the PIN number was wrong."
        end
        session.say msg

      when /^!show/
        msg = "Twitter State : #{user.authorized? ? 'Authorized' : 'Not authorized'}\n"
        session.say msg
        
      when /^!\s/
        message =~ /^!\s+(.*)/
        text = $1
        unless user.authorized?
          session.say """\
Sorry, You are not authorized in twitter yet.
Twitter and I are using OAuth protocol to safely get your authorization.
Please type !oauth command and start authorization.
"""
          return
        end
        if text and not text.empty?
          user.update_twitter(text)
          session.say "OK! success to write #{text} on Twitter"
        else
          session.say "Sorry, Wrong Format! \n EXAMPLE] ! some text"
        end
      when /^!help/i
        session.say help_str
      else
        session.say "I'm Twitter Bot. \nType !help to see what you can do with me."
      end
    end

    def msg_queue_of(email)
      @msg_queue[email] ||= []
    end

    def offline?(email)
      contact = @conn.contactlists["FL"][email]
      contact ? contact.status.code == "FLN" : true
    end

    def check_twitter
      users.each do |email, user|
        next unless user.authorized?
        if offline?(email)
          user.update_since_id
          TwitterBot.debug "==> #{email} if offline..."
          next
        end

        user.twitter_updates.each do |msg|
          TwitterBot.debug "==> Add New Message to #{email} : #{msg}"
          msg_queue_of(email) << msg
        end
        create_session(email) if msg_queue_of(email).size > 0
      end
    end

    def create_session(email)
      if @conn.chatsessions[email]
        TwitterBot.debug "==> Force clear session : #{email}"
        begin @conn.chatsessions[email].close rescue Exception end
        @conn.remove_session(email)
      end
      TwitterBot.debug "==> Request to start new Chat Session : #{email}"
      @conn.start_chat(email, email) 
    end

    def has_user?(tag)
      not users[tag].nil?
    end

    protected
    def users
      @users ||= {}
    end

    def load_users
      filename = @options[:data_file]
      TwitterBot.debug "=> Loading users from #{filename}"
      user_data = File.exist?(filename) ? YAML.load_file(filename) : {}
      user_data.each do |email, data|
        TwitterBot.debug "=> Loading user #{email}"
        users[email] = User.new(email, data.merge(@options[:twitter]))
      end
    end

    def save_users
      TwitterBot.debug "=> Saving users"
      user_data = {}
      users.each do |email, user|
        user_data[email] = user.to_hash
      end
      File.open( @options[:data_file], 'w' ) do |out|
        YAML.dump( user_data, out )
      end
    end

    def find_user(email)
      users[email] ||= User.new(email, @options[:twitter])
    end

    def help_str
      """\
I am Twitter Bot.
I will deliver your timeline updates immediately.
To use me, you need authorization. Please start authorization with !oauth command. Authorization is required just one time.

Commands :
- !oauth : Starts OAuth authorization to use Twitter.
    EXAMPLE : !oauth
- !pin PIN_NUMBER : Enter PIN number that twitter gives to complete OAuth authorization.
    EXAMPLE : !pin 232334
- !show : Shows user's state
- ! TEXT:  Write TEXT on Twitter
    EXAMPLE : ! This text will be in my timeline.
- !help : Shows help
"""
    end
  end
end
