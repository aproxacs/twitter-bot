#!/usr/bin/ruby

$: << File.dirname(__FILE__)

require 'twitter_bot'

CONFIG_FILE = File.join(File.dirname(__FILE__), "..", "config","settings.yml")
unless File.exist?(CONFIG_FILE)
  puts "Configuration file #{CONFIG_FILE} does not exist... exit"
  exit
end

configs = {
  "data_file" => File.join(File.dirname(__FILE__), "..", "config","data.yml"),
  "log_file" => File.join(File.dirname(__FILE__), "..", "log","twitter_bot.log"),
  "interval" => 60,
  "debug" => true
}.merge(YAML.load_file(CONFIG_FILE))

TwitterBot.start(configs)
