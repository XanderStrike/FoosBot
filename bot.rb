require 'slack'
require 'active_record'
require 'sqlite3'

# Settings
BOT_NAME = 'FoosBot'
BOT_CHANNEL  = 'foosbot'
BOT_EMOJI = ':soccer:'


# Configuration
Slack.configure do |config|
  config.token = File.read("key").strip
end

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: 'db/database.sqlite3'
)


# Database Models
class Game < ActiveRecord::Base
  has_many :participates
  has_many :players, through: :participates

  def remain
    4 - players.count
  end
end

class Player < ActiveRecord::Base
  has_many :participates
  has_many :games, through: :participates

  def stats
    "#{username}: #{wins}/#{games.count} (#{win_percentage}%)"
  end

  def wins
    participates.where(win: true).count
  end

  def win_percentage
    100.0 * (wins / games.count)
  end

  def self.standings
    Player.all.sort_by { |player| player.win_percentage }.reverse.map(&:stats)
  end
end

class Participate < ActiveRecord::Base
  belongs_to :game
  belongs_to :player
end


# Classes
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
    @keywords = ['foos', 'in', 'out', 'report', 'abandon', 'stats', 'help', 'ping']
    @bot = bot
    @game = nil
    @state = :idle
    @bot.send_message("Type `!foos` to start a game!")
  end

  def handle message
    @keywords.each do |k|
      if message.text.start_with?("!#{k}")
        player = Player.find_or_create_by(slack_id: message.id, username: message.user)
        self.send(k, message, player)
        return
      end
    end
  end

  private

  def in_progress
    @bot.send_message("There is already a game in progress! Check if the table is clear and `!abandon` if it is!")
  end

  def abandon_game
    @bot.send_message("Game abandoned! :worried:")
    @bot.send_message("Type `!foos` to start a game!")
    @game.destroy
    @game = nil
    @state = :idle
  end

  def foos m, p
    if @state == :searching
      @game.players << p unless @game.players.include?(p)
      if @game.remain <= 0
        @bot.send_message("To the table! Type `!report <victor 1> <victor 2>` to report your results, or `!abandon` to kill the game!")
        @state = :playing
        return
      end
      @bot.send_message("#{m.user} is in! #{@game.remain} more to go!")
    elsif @state == :idle
      @bot.send_message("#{m.user} would like to start a game! Type `!in` to join, or `!out` to leave.")
      @game = Game.create(players: [p])
      @state = :searching
    else
      in_progress
    end
  end

  def in m, p
    foos m, p
  end

  def out m, p
    if @state == :searching
      @game.players.delete(p)
      if @game.remain >= 4
        abandon_game
      end
      @bot.send_message("#{m.user} is out! #{@game.remain} more to go!")
    elsif @state == :playing
      @bot.send_message("You can't leave a game in progress! You can `!abandon` the game if you must.")
    end
  end

  def report m, p
    if @state == :playing
      victors = m.text.split(' ')[1,2].map { |n| n.gsub('@','') }
      @bot.send_message("Congratulations to #{victors.join(' and ')}! Type `!foos` to start a new game!")
      players = Player.where(username: victors).map(&:id)
      @game.participates.where(player_id: players).each {|p| p.update_attributes(win: true) }
      @game.save
      @state = :idle
    end
  end

  def abandon m, p
    if [:playing, :searching].include?(@state)
      abandon_game
    end
  end

  def stats m, p
    args = m.text.split(' ')[1..99]
    if args.count > 0
      output = args.map do |a|
        if a == 'me'
          p.stats
        else
          Player.find_by(username: a).stats
        end
      end
      @bot.send_message(output.join("\n"))
    else
      @bot.send_message("Top 10 Players:\n\t#{Player.standings[0..9].join("\n\t")}")
    end
  end

  def ping m, p
    @bot.send_message("Pong!")
  end

  def help m, p
    str = <<-TEXT
    Commands:
      `!foos` Start a game of foos
      `!in` Join a game
      `!out` Leave a game (before it's started)
      `!report <username> <username>` Report the victors
      `!abandon` Kill an in-progress game
      `!stats` See the top players
      `!stats <username|me>` See a player's stats
      `!help` Show this help text
    TEXT
    @bot.send_message(str)
  end
end


# PID Loop Because Thug Life
bot = Bot.new(BOT_NAME, BOT_CHANNEL, BOT_EMOJI)
mh = MessageHandler.new(bot)
while true
  begin
    new_messages = bot.get_new_messages
    new_messages.each do |m|
      mh.handle(m)
    end
  rescue => e
    puts "Error: #{e}"
  end
  sleep(1)
end
