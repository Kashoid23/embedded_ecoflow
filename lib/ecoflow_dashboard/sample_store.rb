# frozen_string_literal: true

require 'fileutils'

module EcoflowDashboard
  # Append-only storage of station samples, one JSON Lines file per day:
  #   data/samples/2026-11-26.jsonl
  #   {"t":1795666223,"sn":"AAA1","soc":87,"in":0,"out":145,"grid":true}
  class SampleStore
    # About 3 months of daily files; older ones are deleted once a day
    KEEP_DAYS = 92

    def initialize(dir)
      @dir = dir
      FileUtils.mkdir_p(@dir)
      @mutex = Mutex.new
    end

    def append(time, rows)
      return if rows.empty?

      File.open(path(time.to_date), 'a') do |file|
        rows.each { |row| file.puts(JSON.generate(row.merge(t: time.to_i))) }
      end
    end

    # The files are append-only, so the latest day read (today) is kept parsed along with the
    # byte offset it was read up to: a page reload parses only the lines added since.
    # Earlier days are parsed without touching that cache (History keeps their stats).
    def read(date)
      file = path(date)
      return [] unless File.exist?(file)

      @mutex.synchronize do
        return parse(File.read(file)) if @cache && date < @cache[:date]

        @cache = { date: date, offset: 0, rows: [].freeze } if @cache.nil? || date > @cache[:date]
        @cache[:offset] = 0 if File.size(file) < @cache[:offset] # file was replaced: start over
        @cache[:rows] = [].freeze if @cache[:offset].zero?

        added = File.open(file, 'rb') { |f| f.seek(@cache[:offset]) && f.read }
        last  = added.rindex("\n")
        added = last ? added[0..last] : '' # a half-written last line waits for the next read
        @cache[:offset] += added.bytesize
        @cache[:rows] = (@cache[:rows] + parse(added)).freeze unless added.empty?
        @cache[:rows]
      end
    end

    def prune(keep_days: KEEP_DAYS, today: Date.today)
      cutoff = (today - keep_days).iso8601
      Dir[File.join(@dir, '*.jsonl')].each do |file|
        File.delete(file) if File.basename(file, '.jsonl') < cutoff
      end
    end

    private

    def path(date) = File.join(@dir, "#{date.iso8601}.jsonl")

    def parse(text)
      text.each_line.filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil # a line broken by a write cut short when the app was stopped
      end
    end
  end
end
