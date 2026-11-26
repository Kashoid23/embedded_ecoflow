# frozen_string_literal: true

module EcoflowDashboard
  # Daily numbers calculated from the samples of one day.
  #   consumed_wh — stations' output power × time between samples, all stations together
  #   off_minutes — time when no station saw AC input
  #   segments    — [{ from:, to:, state: :on/:off }] in minutes since midnight, for the timeline
  DayStats = Data.define(:consumed_wh, :off_minutes, :segments)

  # Reopened rather than given as a Data.define block: constants set in that block would land
  # on EcoflowDashboard, not on DayStats.
  class DayStats
    # A gap longer than this many sample intervals means the app wasn't running:
    # that time counts as "no data"
    GAP_FACTOR = 3

    def self.max_gap(interval) = interval * GAP_FACTOR

    def self.build(samples, date:, now:, interval:)
      segments = grid_segments(samples, date: date, now: now, interval: interval)

      new(
        consumed_wh: consumed_wh(samples, interval),
        off_minutes: segments.select { |s| s[:state] == :off }.sum { |s| s[:to] - s[:from] },
        segments: segments
      )
    end

    def self.consumed_wh(samples, interval)
      max_gap = self.max_gap(interval)
      samples.group_by { |s| s['sn'] }.sum do |_sn, list|
        list.sort_by { |s| s['t'] }.each_cons(2).sum do |a, b|
          seconds = b['t'] - a['t']
          seconds > max_gap ? 0 : a['out'].to_f * seconds / 3600.0
        end
      end
    end

    def self.grid_segments(samples, date:, now:, interval:)
      max_gap = self.max_gap(interval)
      # One state per sample time: grid is on if any station sees AC input
      ticks = samples.group_by { |s| s['t'] }.filter_map do |t, rows|
        states = rows.map { |r| r['grid'] }.compact
        [t, states.any?] unless states.empty?
      end.sort

      midnight = date.to_time.to_i
      day_end  = [(date + 1).to_time.to_i, now.to_i].min # 23 or 25 h on a DST change day
      minute   = ->(t) { (t - midnight) / 60.0 }

      ticks.each_with_index.each_with_object([]) do |((t, on), i), segments|
        next_t = ticks[i + 1]&.first
        stop   = next_t && next_t - t <= max_gap ? next_t : t + interval
        seg    = { from: minute.call(t), to: minute.call([stop, day_end].min), state: on ? :on : :off }

        last = segments.last
        if last && last[:state] == seg[:state] && (seg[:from] - last[:to]).abs < 0.01
          last[:to] = seg[:to]
        else
          segments << seg
        end
      end
    end

    def no_data? = segments.empty? && consumed_wh.zero?
  end
end
