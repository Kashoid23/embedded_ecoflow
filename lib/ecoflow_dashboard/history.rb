# frozen_string_literal: true

module EcoflowDashboard
  # Day and month stats from the stored samples. Finished days never change, so each is
  # calculated once and kept in memory; only today is rebuilt as new samples come in.
  class History
    # This month so far. days: { Date => DayStats } from the 1st up to today
    Month = Data.define(:days) do
      def consumed_wh = days.values.sum(&:consumed_wh)

      def off_minutes = days.values.sum(&:off_minutes)
    end

    def initialize(store:, interval:)
      @store    = store
      @interval = interval
      @past     = {} # Date => DayStats, only for days before today
      @mutex    = Mutex.new
    end

    def day(date, now:)
      return build(date, now) unless settled?(date, now)

      @mutex.synchronize { @past[date] ||= build(date, now) }
    end

    # today_stats: today's DayStats when the caller already has them, so they aren't built twice
    def month(now, today_stats: nil)
      today = now.to_date
      first = Date.new(today.year, today.month, 1)
      @mutex.synchronize { @past.select! { |date, _| date >= first } } # last month is no longer needed

      Month.new(days: (first..today).to_h { |date| [date, (date == today && today_stats) || day(date, now: now)] })
    end

    private

    # A tick started just before midnight can still append to that day a little after it: the
    # device list and then the quota requests, each up to TIMEOUT to connect plus TIMEOUT to read.
    SETTLE = 4 * HttpJson::TIMEOUT + 60 # s

    def settled?(date, now) = now >= (date + 1).to_time + SETTLE

    def build(date, now) = DayStats.build(@store.read(date), date: date, now: now, interval: @interval)
  end
end
