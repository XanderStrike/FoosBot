require 'slack'
require 'active_record'
require 'sqlite3'

BOT_NAME = 'FoosBot'
BOT_CHANNEL  = 'foosbot'
BOT_EMOJI = ':soccer:'

Slack.configure do |config|
  config.token = File.read("key").strip
end

# ActiveRecord::Base.establish_connection(
#   adapter: 'sqlite3'
#   database: 'db/database.sqlite3'
# )

class Game
  attr_accessor :players, :victors

  def initialize player
    @players = [player]
    @victors = []
  end

  def remain
    4 - @players.count
  end

  def save
    return true
  end
end

# class Player << ActiveRecord::Base

# end

# class PlayedIn << ActiveRecord::Base

# end

class Bot
  attr_accessor :channel, :username, :ids

  def initialize username, channel, emoji
    @channel = convert_channel_to_id channel
    @username = username
    @emoji = emoji
    @oldest_message = nil

    @ids = {}
    refresh_ids

    send_message('Initialized!')
  end

  def send_message text
    response = Slack.chat_postMessage(username: @username, channel: @channel, text: text, icon_emoji: @emoji)
    puts "Sent: #{text}"
    @oldest_message = response['ts']
  end


  def get_new_messages
    response = Slack.channels_history(channel: @channel, oldest: @oldest_message)
    @oldest_message = response['messages'].first['ts'] unless response['messages'].empty?

    messages = response['messages'].reverse # messages are most recent first of course

    messages = messages.map do |m_hash|
      Message.new(@ids[m_hash['user']], m_hash['user'], m_hash['text'])
    end

    return messages
  end

  def set_topic text
    puts "Set the topic to #{text}"
    puts Slack.channels_setTopic(channel: @channel, topic: text)
  end

  private

  def get_username id
    refresh_ids if @ids[id].nil?
    @ids[id]
  end

  def refresh_ids
    response = Slack.users_list
    response['members'].map do |r|
      @ids[r['id']] = r['name']
    end
  end

  def convert_channel_to_id channel_name
    Slack.channels_list['channels'].each do |c|
      return c['id'] if c['name'] == channel_name
    end
  end
end


class Message
  attr_accessor :user, :text, :id

  def initialize user, id, text
    @user = user
    @id = id
    @text = text
  end

  def to_s
    "#{@user}: #{@text}"
  end

  def self.find messages, str
    messages.each do |m|
      if m.text.start_with?(str)
        return m
      end
    end
    nil
  end
end


class MessageHandler
  # states = [:idle, :searching, :playing]

  def initialize bot
    @keywords = ['foos', 'in', 'out', 'report', 'abandon', 'stats', 'help']
    @bot = bot
    @game = nil
    @state = :idle
    @bot.send_message("Type `!foos` to start a game!")
  end

  def handle message
    @keywords.each do |k|
      if message.text.start_with?("!#{k}")
        self.send(k, message)
        return
      end
    end
  end

  private

  def in_progress
    @bot.send_message("There is already a game in progress! Check if the table is clear and `!abandon` if it is!")
  end

  def foos m
    if @state == :searching
      @game.players << m.user # unless @game.players.include?(m.user) TODO
      if @game.remain == 0
        @bot.send_message("To the table! Type `!report <victor 1> <victor 2>` to report your results, or `!abandon` to kill the game!")
        @state = :playing
        return
      end
      @bot.send_message("@#{m.user} is in! #{@game.remain} more to go!")
    elsif @state == :idle
      @bot.send_message("@#{m.user} would like to start a game! Type `!in` to join, or `!out` to leave.")
      @game = Game.new(m.user)
      @state = :searching
    else
      in_progress
    end
  end

  def in m
    foos m
  end

  def out m
    if @state == :searching
      @game.players.delete(m.user)
      if @game.remain == 4
        @bot.send_message("Game abandoned! Type `!foos` to start a new game!")
        @state = :idle
        return
      end
      @bot.send_message("@#{m.user} is out! #{@game.remain} more to go!")
    end
  end

  def report m
    if @state == :playing
      @game.victors = m.text.split(' ')[1,2].map { |n| n.gsub('@','') }
      @bot.send_message("Congratulations to #{@game.victors.join(' and ')}! Type `!foos` to start a new game!")
      @game.save
      @state = :idle
    end
  end

  def abandon m
    if [:playing, :searching].include?(@state)
      @bot.send_message("Game abandoned! :worried:")
      @bot.send_message("Type `!foos` to start a game!")
      @game = nil
      @state = :idle
    end
  end

  def stats m
    @bot.send_message("There are no stats yet silly!")
  end

  def help m
    str = <<-TEXT
    Commands:
      `!foos` Start a game of foos
      `!in` Join a game
      `!out` Leave a game (before it's started)
      `!report <victor 1> <victor 2>` Report the victors
      `!abandon` Kill an in-progress game
      `!stats` See the top players
      `!stats <name>` See a player's stats
      `!help` Show this help text
    TEXT
    @bot.send_message(str)
  end
end


# pid loop cuz thug life

bot = Bot.new(BOT_NAME, BOT_CHANNEL, BOT_EMOJI)
mh = MessageHandler.new(bot)
while true
  new_messages = bot.get_new_messages
  new_messages.each do |m|
    mh.handle(m)
  end
  sleep(1)
end
