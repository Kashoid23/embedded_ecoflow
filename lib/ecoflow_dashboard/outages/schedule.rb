# frozen_string_literal: true

module EcoflowDashboard
  module Outages
    # The latest outage schedule (today and, once published, tomorrow), kept in memory.
    # It's downloaded again every few minutes, so nothing needs to be stored on disk.
    #
    # days: { Date => [[from_minute, to_minute, :definite | :possible], ...] }
    #   :definite — no power by schedule, :possible — power may be cut
    class Schedule
      def initialize
        @days  = {}
        @mutex = Mutex.new
      end

      def replace(days)
        @mutex.synchronize { @days = days }
      end

      def known?(date) = @mutex.synchronize { @days.key?(date) }

      # Planned outages as minute ranges: [[480, 750], [960, 1200]]
      def outages(date) = ranges(date, :definite)

      def possible(date) = ranges(date, :possible)

      def planned_minutes(date) = outages(date).sum { |from, to| to - from }

      # Next change by the schedule: { state: :off, from: Time, until: Time } (outage now, from its start)
      # or { state: :on, until: Time } (next outage starts), nil when none is planned.
      def next_change(now)
        today  = now.to_date
        events = [today, today + 1].flat_map do |date|
          outages(date).map { |from, to| [at(date, from), at(date, to)] }
        end
        events = merge_touching(events.sort) # 22:00–24:00 + 00:00–02:00 is one outage until 02:00

        if (current = events.find { |from, to| now >= from && now < to })
          { state: :off, from: current.first, until: current.last }
        elsif (upcoming = events.map(&:first).select { |from| from > now }.min)
          { state: :on, until: upcoming }
        end
      end

      private

      def ranges(date, type)
        slots = @mutex.synchronize { @days.fetch(date, []) }
        slots.select { |_, _, t| t == type }.map { |from, to, _| [from, to] }
      end

      # Wall-clock minutes of a day -> local Time (right on DST change days too; 1440 = next midnight)
      def at(date, minutes)
        day, minutes = minutes.divmod(1440)
        date += day
        Time.new(date.year, date.month, date.day, minutes / 60, minutes % 60)
      end

      # Sorted [from, to] Time pairs -> overlapping or touching pairs joined
      def merge_touching(events)
        events.each_with_object([]) do |(from, to), merged|
          if merged.any? && from <= merged.last[1]
            merged.last[1] = [merged.last[1], to].max
          else
            merged << [from, to]
          end
        end
      end
    end
  end
end
