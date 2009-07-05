module TwitterBot
  class User
    # config is twitter config : ckey, csecret
    def initialize(email, config = {})
      @email = email
      @config = config
      init_twitter
    end

    def authorized?
      !@twitter.nil?
    end

    def request_token
      # reset oauth
      @oauth = Twitter::OAuth.new(@config[:ckey], @config[:csecret])
      @request_token = @oauth.request_token
    end

    def complete_oauth(digits)
      return unless @request_token
      begin
        acc_token = @request_token.get_access_token({}, {:oauth_verifier => digits})
      rescue Exception => e
        TwitterBot.log.info e if TwitterBot.log
        return
      end

      @config[:akey] = acc_token.token
      @config[:asecret] = acc_token.secret

      init_twitter
    end

    def update_since_id
      updates = @twitter.friends_timeline(:since_id => @since_id)
      @since_id = updates.first.id unless updates.empty?
    end

    def twitter_updates
      return [] unless authorized?
      updates = @twitter.friends_timeline(:since_id => @since_id)
      @since_id = updates.first.id unless updates.empty?
      updates.map do |status|
        "(mp) #{status.user.screen_name} says : \n#{status.text}"
      end
    end

    def update_twitter(text)
      return unless authorized?
      @twitter.update(text)
    end

    def to_hash
      {
        :akey => @config[:akey],
        :asecret => @config[:asecret]
      }
    end

    protected
    def init_twitter
      if @config[:akey] and @config[:asecret]
        oauth.authorize_from_access(@config[:akey], @config[:asecret])
        @twitter = Twitter::Base.new(oauth)
        @since_id = @twitter.friends_timeline.first.id
      end
    end
    def oauth
      @oauth ||= Twitter::OAuth.new(@config[:ckey], @config[:csecret])
    end
  end
end
