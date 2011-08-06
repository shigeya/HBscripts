# -*- coding: utf-8 -*-

require 'time'

module HandBrake

  class CLI
    @@cli = "/Applications/HandBrakeCLI"
    unless File.exists? @@cli
      @@cli += "-Cur" if File.exists? @@cli + "-Cur"
      @@cli += "-current" if File.exists? @@cli + "-current"
    end

    def self.exec_capture(cmd)
      `#{cmd} 2>&1`
    end

    def self.scan(file)
      self.exec_capture("#{@@cli} -i '#{file}' -t 0")
    end
  end

  class Chapter
    attr_reader :params, :chapter, :duration

    def initialize(params)
      @params = params
      @chapter = params[:chapter]
      @duration = params[:duration]
    end
  end

  class Title
    include Enumerable

    attr_reader :params, :title, :chapters

    def initialize(params)
      @params = params
      @chapters = [ ]
      @params[:chapters].each do |k,v|
        @chapters << Chapter.new(v)
      end
      @title = params[:title]
    end

    def each
      @chapters.each { |v| yield v }
    end

    def total_duration
      base = Time.parse("00:00:00")
      base += @chapters.map{|v| Time.parse(v.duration) - base }.inject(:+)
      base.strftime("%H:%M:%S")
    end
  end

  class Disc
    include Enumerable

    attr_reader :filename, :params, :main_feature, :titles

    def initialize(file)
      @filename = file
      @main_feature = nil
      @titles = { }
      read
      @params[:titles].each do |k,v|
        title = Title.new(v)
        @titles[ v[:title] ] = title
        @main_feature = title if v[:main_feature] == true
      end
    end

    def each
      @titles.each { |k,v| yield v }
    end

    def read
      r = CLI::scan(@filename)
      list = { :titles=> { } }
      cur = nil
      r.split(/\n/).grep(/^(\s|\+)/).each do |l|
        l.sub!(/^\s+/, '')
        case l
        when /\+ title (\d+):/
          list[:titles][cur[:title]] = cur if cur != nil
          cur = { :title => $1.to_i }
        when /\+ Main Feature/
          cur[:main_feature] = true
        when /\+ vts (\d+), ttn (\d), cells (\d+)\-\>(\d+) \((\d+) blocks\)/
          cur[:vts] = $1.to_i
          cur[:ttn] = $2.to_i
          cur[:cell_from] = $3.to_i
          cur[:cell_to] =  $4.to_i
          cur[:blocks] = $5.to_i
        when /\+ duration: (\d\d:\d\d:\d\d)/
          cur[:duration] = $1
        when /\+ autocrop: (\d+)\/(\d+)\/(\d+)\/(\d+)/
          cur[:autocrop] = [$1.to_i, $2.to_i, $3.to_i, $4.to_i]
        when /\+ size: (\d+)x(\d+), pixel aspect: (\d+)\/(\d+), display aspect: (\d+\.\d+), (\d+\.\d+) fps/
          cur[:size] = [$1.to_i, $2.to_i]
          cur[:pixel_aspect] = [$3.to_i, $4.to_i]
          cur[:display_aspect] = $5.to_f
          cur[:fps] = $6
        when /\+ chapters:/
          cur[:chapters] = { }
        when /\+ (\d+): cells (\d+)\-\>(\d+), (\d+) blocks, duration (\d\d:\d\d:\d\d)/
          cur[:chapters][$1.to_i] = { :chapter=>$1.to_i, :cell_from=>$2.to_i, :cell_to=>$3.to_i, :blocks=>$4.to_i, :duration=>$5 }
        when /\+ audio tracks:/
          cur[:audio_tracks] = { }
        when /\+ (\d+), ([^,]+), ([^,]+)Hz, ([^,]+)bps/
          cur[:audio_tracks][$1.to_i] = { :type=>$2, :hz=>$3, :bps=>$4 }
        when /\+ subtitle tracks:/
          cur[:subtitle_tracks] = { }
# NEED TO HANDLE SUBTITLE TRACKS          
        else
          STDERR.puts ">> NOT HANDLED: #{l}"
        end
      end
      list[cur[:track_no]] = cur
      @params = list
    end
  end

end
