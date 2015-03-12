require "slack"

username = 'FoosBot'
channel  = 'foosbot'

Slack.configure do |config|
  config.token = File.read("key").strip
end

# methods
def send_message text
  Slack.chat_postMessage(username: 'FoosBot', channel: '#foosbot', text: text)
end

# run like the wind
puts "Connecting..."
if Slack.auth_test['ok']
  puts "Success!"
else
  puts "Failed!?"
end

send_message("Hello World!")
