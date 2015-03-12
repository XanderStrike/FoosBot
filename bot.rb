require "slack"

BOT_NAME = 'FoosBot'
BOT_CHANNEL  = 'foosbot'

Slack.configure do |config|
  config.token = File.read("key").strip
end


class Bot
  attr_accessor :channel, :username, :ids

  def initialize username, channel
    @channel = convert_channel_to_id channel
    @username = username
    @oldest_message = nil

    @ids = {}
    refresh_ids

    send_message('Initialized!')
  end

  def send_message text
    response = Slack.chat_postMessage(username: @username, channel: @channel, text: text)
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


class MessageHandler

  # states = [:idle, :searching, :playing]

  def initialize bot
    @keywords = ['foos', 'in', 'out', 'report', 'abandon']
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

  def foos m
    if @state == :idle
      @bot.send_message("@#{m.user} would like to start a game! Type `!in` to join, or `!out` to leave.")
      @game = Game.new(m.user)
      @state = :searching
    end
  end

  def in m
    if @state == :searching
      @game.players << m.user# unless @game.players.include?(m.user)
      if @game.remain == 0
        @bot.send_message("To the table! Type `!report <victor 1> <victor 2>` to report your results, or `!abandon` to kill the game!")
        @state = :playing
        return
      end
      @bot.send_message("@#{m.user} is in! #{@game.remain} more to go!")
    end
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
end


# pid loop cuz thug life

bot = Bot.new(BOT_NAME, BOT_CHANNEL)
mh = MessageHandler.new(bot)
while true
  new_messages = bot.get_new_messages
  new_messages.each do |m|
    mh.handle(m)
  end
  sleep(1)
end
