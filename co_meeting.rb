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
    Meeting.new(get("/meetings/show?meeting_id=#{meeting_id}"))
  end

  def attachment(attachment_id)
    get("/attachments/show?attachment_id=#{attachment_id}")
  end

  private
  def mashize(response)
    Mash.new(JSON.parse(response.body)['result'])
  end

  class Meeting
    attr_reader :mash # debug usage
    attr_reader :title, :creator, :note, :discussion

    def initialize(mash)
      @mash = mash

      @title = mash.title
      @creator = mash.creator

      @note = Note.new(mash.note)

      # parse discussion blips into multi-rooted tree structure
      @discussion = mash.discussion.rootThread.blipIds.map{|root_id|
        Blip.expand(root_id, mash.discussion)
      }
    end

    def all_attachments
      @discussion.map{|b| b.all_attachments }.flatten
    end

    def dump
      @discussion.map{|b| b.dump}
    end

    class Blip
      attr_reader :creator, :updated, :content, :children
      attr_accessor :attachments

      def self.expand(blipid, discussion)
        found = discussion.blips.find{|bid, data| bid == blipid }
        return nil unless found
        Blip.new(found.last, discussion)
      end

      def initialize(data, discussion)
        @creator = data.creator
        @updated = data.lastModifiedTime

        @content = data.content

        # TODO: APIでattachment取得
        # http://co-meeting.github.io/api/attachments/show.html
        @attachments = data.elements.select{|id, val|
          val.type == 'ATTACHMENT'
        }.map{|id, val|
          val.properties # .attachmentId
        }

        @children = if data.childBlipIds.count.zero?
                      []
                    else
                      data.childBlipIds.map{|child_id|
                        Blip.expand(child_id, discussion)
                      }
                    end
      end

      def to_s(time: false)
        suffix = time ? "\n(#{@updated})" : nil
        "[#{@creator}]#{@content}#{suffix}"
      end

      def dump
        if @children.count.zero?
          to_s
        else
          [to_s, @children.map{|c| c.dump }]
        end
      end

      def all_attachments
        if @children.count.zero?
          @attachments
        else
          @attachments + @children.map{|c| c.all_attachments }
        end
      end
    end

    class Note
      attr_reader :attachments, :content

      def initialize(mash)
        @attachments = mash.elements.select{|id, val|
          val.type == 'ATTACHMENT'
        }.map{|id, val|
          val.properties
        }

        @content = mash.content
      end
    end
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

