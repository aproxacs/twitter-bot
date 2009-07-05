%w(rubygems activesupport eventmachine twitter yaml).each {|l| require l}

require 'msn/msn'
require 'twitter_bot/worker'
require 'twitter_bot/msn_hanler'
require 'twitter_bot/user'

module TwitterBot
  def self.start(options = {})
    @options = self.deep_symbolize_keys(options)
    set_log(@options[:log_file])
    MsnHandler.new(@options).start
  end

  mattr_accessor :log
  def self.info msg
    p msg
    self.log.info msg if self.log
  end
  def self.error msg
    p msg
    self.log.error msg if self.log
  end
  def self.debug msg
    p msg
    self.log.debug msg if self.log and self.debug?
  end

  def self.deep_symbolize_keys(hash)
    hash.inject({}) { |result, (key, value)|
      value = deep_symbolize_keys(value) if value.is_a? Hash
      result[(key.to_sym rescue key) || key] = value
      result
    }
  end

  private
  def self.set_log(filename)
    FileUtils.mkdir_p(File.dirname(filename))
    self.log = Logger.new(filename)
  end
  def self.debug?
    @options[:debug]
  end
end
