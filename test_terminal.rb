require 'slack'

Slack.configure do |config|
  config.token = File.read("key").strip
end

channel = '#foosbot'

print "Username: "
username = gets.chomp

while true
  print "> "
  m = gets.chomp
  Slack.chat_postMessage(username: username, channel: channel, text: m)
end
