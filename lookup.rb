require 'json'
require 'oauth'
require 'oauth/request_proxy/typhoeus_request'
require 'optparse'
require 'typhoeus'

TEAM_ID_KEY = 'team_id'
SUB_TEAMS_KEY = 'sub_teams'
MEMBERS_KEY = 'members'
NAME_KEY = 'name'
DISCORD_KEY = 'discord'
TWITTER_KEY = 'twitter'
GETTR_KEY = 'gettr'
STATS_KEY = 'stats'
TIMESTAMP_KEY = 'timestamp'
CHECKIN_KEY = 'checkin'
DAILY_KEY = :daily
MEETING_KEY = :meeting

###########
# TWITTER #
###########

def get_request_token(consumer)

	request_token = consumer.get_request_token()

  return request_token
end

def get_user_authorization(request_token)
	puts "Follow this URL to have a user authorize your app: #{request_token.authorize_url()}"
	puts "Enter PIN: "
	pin = gets.strip
  
  return pin
end

def obtain_access_token(consumer, request_token, pin)
	token = request_token.token
	token_secret = request_token.secret
	hash = { :oauth_token => token, :oauth_token_secret => token_secret }
	request_token  = OAuth::RequestToken.from_hash(consumer, hash)
	
	# Get access token
	access_token = request_token.get_access_token({:oauth_verifier => pin})

	return access_token
end

def user_lookup(url, oauth_params, query_params)
	options = {
	    :method => :get,
	    headers: {
	     	"User-Agent": "v2UserLookupRuby"
	    },
	    params: query_params
	}
	request = Typhoeus::Request.new(url, options)
	oauth_helper = OAuth::Client::Helper.new(request, oauth_params.merge(:request_uri => url))
	request.options[:headers].merge!({"Authorization" => oauth_helper.header}) # Signs the request
	response = request.run

	return response
end

def make_query_params(users)
	groups = users.each_slice(100).to_a
	groups.map do |batch|
		{'usernames': batch.join(','), 'user.fields': 'public_metrics'}
	end
end

def twitter_stats(users)
	consumer_key = ENV["CONSUMER_KEY"]
	consumer_secret = ENV["CONSUMER_SECRET"]

	# Returns a user object for one or more users specified by the requested usernames
	user_lookup_url = "https://api.twitter.com/2/users/by"

	consumer = OAuth::Consumer.new(consumer_key, consumer_secret,
	                                :site => 'https://api.twitter.com',
	                                :authorize_path => '/oauth/authenticate',
	                                :debug_output => false)

	# PIN-based OAuth flow - Step 1
	request_token = get_request_token(consumer)
	# PIN-based OAuth flow - Step 2
	pin = get_user_authorization(request_token)
	# PIN-based OAuth flow - Step 3
	access_token = obtain_access_token(consumer, request_token, pin)

	oauth_params = {:consumer => consumer, :token => access_token}

	member_tweets = {}
	make_query_params(users).each do |query_params|
		response = user_lookup(user_lookup_url, oauth_params, query_params)

		if response.code == 200
			body = JSON.parse(response.body)
			puts "Errors: #{body['errors']}" if body['errors'].nil? == false
			body['data'].each do |user_data|
				member_tweets[user_data['username']] = user_data['public_metrics']['tweet_count']
			end
		else
			exit 1
		end
		sleep(3)
	end

	member_tweets
end

#########
# STATS #
#########

def make_stats(time, twitter_count, gettr_count)
	timestamp = time.strftime('%Y/%m/%d/%a')
	{timestamp: {TWITTER_KEY: twitter_count, GETTR_KEY: gettr_count}}
end

#########
# TEAMS #
#########

options = {}
OptionParser.new do |opts|
    opts.banner = "Usage: lookup.rb [options]"

	opts.on('-c', '--checkin INPUT', 'Checkin records for the week') { |v| options[:checkin_file] = v }
    opts.on('-i', '--input INPUT', 'Input file name') { |v| options[:input_file] = v }
    opts.on('-o', '--output OUTPUT', 'Output file name') { |v| options[:output_file] = v }

end.parse!

file = File.read(options[:input_file])
teams = JSON.parse(file)

twitter_users = []
teams.each do |team|
	team[SUB_TEAMS_KEY].each do |sub_team|
		sub_team[MEMBERS_KEY].each do |member|
			twitter_users.append(member[TWITTER_KEY])
		end
	end
end

# Checkin Stats

class String
	def is_meeting_checking?
	include?('暢想') || include?('畅想')
	end
	def is_daily_checking?
	(include?('簽到') || include?('签到')) && is_meeting_checking? == false
	end
end

def checkin_stats(input_file)
	stats = {}
	regex = /\[.*\] (.*): (.*)/
	File.readlines(input_file).each do |checkin_line|
		line = checkin_line.strip
		match = line.match(regex)
		raise 'Invalid checkin line: #{line}!' if match.nil?
		name = match[1]
		checkin = match[2]
		if stats[name].nil?
			stats[name] = {DAILY_KEY => 0, MEETING_KEY => 0}
		end
		member_checkin = stats[name]
		current_daily_checkin = stats[name][DAILY_KEY]
		current_meeting_checkin = stats[name][MEETING_KEY]
		if checkin.is_meeting_checking?
			stats[name][MEETING_KEY] = current_meeting_checkin + 1
		elsif checkin.is_daily_checking?
			stats[name][DAILY_KEY] = current_daily_checkin + 1
		else
			raise 'Unrecognized checking text: #{line}!'
		end
	end
	stats
end

# Summarise

twitter_stats = twitter_stats(twitter_users)
checkin_stats = checkin_stats(options[:checkin_file])

stats = teams
now = Time.now
timestamp = now.strftime('%Y/%m/%d/%a')
weekstamp = now.strftime('%Y/%V')
stats.each do |team|
	team[SUB_TEAMS_KEY].each do |sub_team|
		sub_team[MEMBERS_KEY].each do |member|
			if member[STATS_KEY].nil?
				member[STATS_KEY] = []
			end

			daily_checkin = checkin_stats[member[NAME_KEY]][DAILY_KEY] || 0
			meeting_checkin = checkin_stats[member[NAME_KEY]][MEETING_KEY] || 0
			member_stats = {'timestamp': timestamp,
							'week': weekstamp,
							'twitter': twitter_stats[member[TWITTER_KEY]],
							'gettr': '0',
							'daily_checkin': daily_checkin,
							'meeting_checkin': meeting_checkin}
			member[STATS_KEY].append(member_stats)
			member[STATS_KEY].sort_by { |mstats| mstats[TIMESTAMP_KEY] }
		end
	end
end

puts JSON.pretty_generate(stats)
