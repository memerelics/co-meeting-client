require 'bundler/setup'
Bundler.require

class CoMeeting
  include Hashie

  PREFIX = '/api/v1'

  def initialize(conffile='secret.yml')
    @conf = Mash.load(conffile)
    client = OAuth2::Client.new(@conf.client, @conf.secret, site: 'https://www.co-meeting.com')
    puts client.auth_code.authorize_url(redirect_uri: @conf.callback)
    print 'Copy & Paste authorization_code from above url: '
    authorization_code = gets.chomp
    @access_token = client.auth_code.get_token(authorization_code, redirect_uri: @conf.callback)
  end

  def get(path)
    mashize(@access_token.get("#{PREFIX}#{path}"))
  end

  def bioit_group
    @bioit_group ||= group(@conf.bioit_group_id)
  end

  # include_meetings: 1にすることで最新更新meeting10件まで取得可能. もっとほしい
  def group(group_id)
    get("/groups/show?id=#{group_id}&include_meetings=1")
  end

  def meeting(meeting_id)
    get("/meetings/show?meeting_id=#{meeting_id}")
  end

  private def mashize(response)
    Mash.new(JSON.parse(response.body)['result'])
  end
end

cmtg = CoMeeting.new
puts cmtg.bioit_group.meetings.map{|m| m.title }

meeting = cmtg.meeting(cmtg.bioit_group.meetings.first.id)

messages = meeting.discussion.blips.values
messages.sample(5).each do |v|
  puts "#{v.creator}: #{v.content}"
end

# http://co-meeting.github.io/api/meetings/show.html#section-3
# meetings.first.keys
#  => ["annotations",
#      "properties",
#      "elements",
#      "blipId",
#      "childBlipIds",
#      "contributors",
#      "creator",
#      "content",
#      "lastModifiedTime",
#      "parentBlipId",
#      "version",
#      "replyThreadIds",
#      "threadId"]

