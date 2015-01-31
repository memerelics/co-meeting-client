require 'bundler/setup'
Bundler.require
require 'erb'
require 'open-uri'
require 'base64'

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
    Attachment.new(get("/attachments/show?attachment_id=#{attachment_id}"))
  end

  private
  def mashize(response)
    Mash.new(JSON.parse(response.body)['result'])
  end

  class Meeting
    attr_reader :mash # debug usage
    attr_reader :title, :updated_at, :creator, :note, :discussion

    def initialize(mash)
      @mash = mash

      @title = mash.title
      @updated_at = Time.parse(mash.updated_at)
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
      attr_reader :creator, :updated_at, :content, :children
      attr_accessor :attachments

      def self.expand(blipid, discussion)
        found = discussion.blips.find{|bid, data| bid == blipid }
        return nil unless found
        Blip.new(found.last, discussion)
      end

      def initialize(data, discussion)
        @creator = data.creator
        @updated_at = Time.parse(data.lastModifiedTime)

        @content = data.content

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
        suffix = time ? "\n(#{@updated_at})" : nil
        "[#{@creator}]#{@content}#{suffix}"
      end

      def dump
        if @children.count.zero?
          to_s
        else
          [to_s, @children.map{|c| c.dump }]
        end
      end

      def to_html(lv: 0)
        lv = 5 if lv > 5

        output = "<div class='message #{lv.zero? ? '' : 'res'} lv#{lv}'>
        [#{@creator}] #{filter(@content)}
        #{attachment_tags(@attachments)}
        <br />
        </div>"

        unless @children.count.zero?
          output << @children.map{|c| c.to_html(lv: lv + 1) }.join
        end

        output
      end

      def filter(content)
        out = content
        out = out.gsub(/^\n/, '')
        out = out.gsub(/\n/, '<br />')
        out = Rinku.auto_link(out, :urls, 'target="_blank"')
        out
      end

      def attachment_tags(attachments)
        attachments.map {|a| "<attachment id='#{a.attachmentId}' />" }.join
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

        @content = Rinku.auto_link(mash.content, :urls, 'target="_blank"')
      end
    end
  end

  class Attachment

    def initialize(data)
      @file_name     = data.file_name
      @url           = data.url
      @thumbnail_url = data.thumbnail_url
      @content_type  = data.content_type
    end

    def to_tag
      return "<a class='attachment' href='#{url}'>#{@file_name}</a>" unless @content_type.include?('image')
      base64 = Base64.encode64(open(@url).read) rescue nil
      return "<p>no image</p>" unless base64
      "<img class='attachment' src='data:#{@content_type};base64,#{base64}' />"
    end
  end
end

cmtg = CoMeeting.new
# puts cmtg.bioit_group.meetings.map{|m| m.title }

meeting = cmtg.meeting(cmtg.bioit_group.meetings[2].id)

html = ''
html << "<div class='meta'>
        #{meeting.title} <br />
        #{meeting.updated_at.strftime('%Y-%m-%d')}
        </div>"
html << "<div class='note'>#{meeting.note.content}</div>" if meeting.note.content.length > 1
html << meeting.discussion.map {|root| "<div class='box'>#{root.to_html}</div>" }.join

meeting.all_attachments.each do |a|
  attachment = cmtg.attachment(a.attachmentId)
  html = html.gsub(/<attachment.*?#{a.attachmentId}.*?\/>/, attachment.to_tag)
end

erb = ERB.new(open('./template.html.erb').read)
open("#{ENV['HOME']}/Desktop/fa.html", "w+") do |f|
  f.write(erb.result(binding))
end
