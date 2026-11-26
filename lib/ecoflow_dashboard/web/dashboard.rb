# frozen_string_literal: true

module EcoflowDashboard
  module Web
    # Everything the dashboard shows for today, from samples and the schedule.
    class Dashboard
      include Helpers

      # Below this total output the backup estimate is meaningless (and huge)
      MIN_LOAD_WATTS = 5

      # Battery capacity in Wh, by productName, of models that don't report their remaining charge
      MODEL_CAPACITY = { 'RIVER 2 Pro' => 768 }.freeze

      GRID_TONE = { on: :ok, off: :bad }.freeze
      GRID_LABEL = { on: 'on grid', off: 'on battery' }.freeze

      attr_reader :now, :devices, :settings, :weather # weather: Weather::Report, nil until the first fetch

      def initialize(now:, devices:, history:, schedule:, settings:, weather: nil, air_raid: nil)
        @now      = now
        @devices  = devices
        @history  = history
        @schedule = schedule
        @settings = settings
        @weather  = weather
        @air_raid = air_raid
      end

      # :active / :partial / :none, :unknown when not fetched yet or stale,
      # nil when no AIR_RAID_PROVIDER is set
      def air_raid
        return unless settings.air_raid?

        @air_raid ? @air_raid.state_at(now) : :unknown
      end

      def today = now.to_date

      def now_minute = now.hour * 60 + now.min + now.sec / 60.0

      def stats = @stats ||= @history.day(today, now: now)

      # This month so far, today included: consumed_wh, off_minutes, days
      def month = @month ||= @history.month(now, today_stats: stats)

      # ----- tiles: { label:, value:, tone:, sub:, sub_tone: } -----

      def off_tile
        { label: 'Without power today', value: short_duration(stats.off_minutes), tone: 'bad',
          sub: ("of #{short_duration(@schedule.planned_minutes(today))}" if schedule? && @schedule.known?(today)) }
      end

      def consumed_tile
        { label: 'Consumed today', value: energy(stats.consumed_wh), sub: load_line, sub_tone: 'accent' }
      end

      # Total output of the stations that answered, W
      def load_watts = @load_watts ||= readable.sum { |d| d.values['pd.wattsOutSum'].to_f }

      # Hours the stored energy lasts at the current load, nil when it can't be told
      def backup_hours
        return if load_watts < MIN_LOAD_WATTS

        stored = readable.sum { |d| stored_wh(d) || 0 }
        (stored / load_watts).round if stored.positive?
      end

      # Energy left in a station, Wh: remaining charge × pack voltage as its battery reports them,
      # else charge % of the model's capacity; nil when neither is known
      def stored_wh(device)
        mah, mv = device.values.values_at(*Sampler::BATTERY_KEYS)
        return mah * mv / 1_000_000.0 if mah && mv

        capacity = MODEL_CAPACITY[device.name]
        capacity * device.values['pd.soc'].to_f / 100 if capacity
      end

      def schedule? = settings.schedule?

      # ----- grid -----

      # :on / :off, or nil when there is no recent sample
      def grid = current&.fetch(:state)

      # The grid state now and when it began: { state: :on / :off, since: Time }, nil without a recent
      # sample. A state that began yesterday is carried over midnight from yesterday's samples.
      def current
        return @current if defined?(@current)

        last = stats.segments.last
        prev = yesterday_tail if last.nil? || last[:from] < 0.01 # only a state from midnight can carry over
        @current =
          if last
            since = time_at(today, last[:from])
            since = prev[:since] if prev && prev[:state] == last[:state] && since - prev[:until] < 1
            { state: last[:state], since: since } if now - time_at(today, last[:to]) <= max_gap
          elsif prev && now - prev[:until] <= max_gap # no sample today yet, right after midnight
            prev.slice(:state, :since)
          end
      end

      # The status banner at the top:
      #   title, tone — power on / no power / waiting for data
      #   detail      — "since 10:00"
      #   next        — right column: { label:, value:, sub: } countdown to the next change by the schedule
      #   progress    — % of the scheduled outage passed, only while there is no power during one
      def banner
        { title: { on: 'Power on', off: 'No power' }.fetch(grid, 'Waiting for data'),
          tone: GRID_TONE.fetch(grid, :muted),
          detail: banner_detail, next: banner_next,
          progress: (outage_pct if grid == :off && scheduled_off?) }
      end

      # ----- schedule -----

      def next_change
        return @next_change if defined?(@next_change)

        @next_change = @schedule.next_change(now)
      end

      # A scheduled outage is in progress right now
      def scheduled_off? = next_change&.fetch(:state) == :off

      # Today's planned outages: [{ from:, to:, when: :past / :now / :next / :later }]
      def outages_today
        @outages_today ||= begin
          list = @schedule.outages(today)
          coming = list.index { |from, _| from > now_minute }
          list.each_with_index.map do |(from, to), i|
            phase = if to <= now_minute then :past
                    elsif from <= now_minute then :now
                    elsif i == coming then :next
                    else :later
                    end
            { from: from, to: to, when: phase }
          end
        end
      end

      # ----- timeline -----

      # One track for the day: planned outages, then what the stations saw drawn over them —
      # so history replaces the plan up to now and the schedule shows for the rest of the day.
      #   { segments: [{ from:, to:, css: "plan" | "maybe" | "on" | "off" }], note: }
      # note explains an empty track ("no data yet") or a missing schedule.
      def timeline
        plan   = planned_segments
        actual = stats.segments.map { |s| { from: s[:from], to: s[:to], css: s[:state].to_s } }
        note   = (['no data yet', (schedule_note(plan) if schedule?)].compact.join(' · ') if actual.empty?)
        { segments: plan + actual, note: note }
      end

      # ----- stations -----

      # Why a station has no readings to show: "unavailable" (API error), "offline", or nil
      def problem(device)
        if device.error then 'unavailable'
        elsif !device.online then 'offline'
        end
      end

      # Battery charge of a station, 0–100
      def soc(device) = device.values['pd.soc'].to_i.clamp(0, 100)

      # [text, tone] for a station's status chip: what the station itself runs from,
      # or the house's grid state when the station can't tell (nothing flowing)
      def status(device)
        issue = problem(device)
        return [issue, :muted] if issue

        state = { true => :on, false => :off }.fetch(device.grid) { grid }
        [GRID_LABEL.fetch(state, '—'), GRID_TONE.fetch(state, :muted)]
      end

      private

      def readable = @readable ||= devices.reject { |d| problem(d) }

      def max_gap = DayStats.max_gap(settings.sample_interval) # s

      # DayStats minutes are elapsed since midnight (not wall clock), so this is right on DST change days
      def time_at(date, minutes) = date.to_time + minutes * 60

      # Yesterday's last segment when it ran up to midnight: { state:, since:, until: } with Times
      def yesterday_tail
        date = today - 1
        last = @history.day(date, now: now).segments.last
        return unless last

        ends = time_at(date, last[:to])
        { state: last[:state], since: time_at(date, last[:from]), until: ends } if today.to_time - ends < 1
      end

      def load_line
        ["now #{load_watts.round} W", ("backup ~#{backup_hours} h" if backup_hours)].compact.join(' · ')
      end

      def banner_detail
        return 'no recent samples from the stations' unless grid

        started = current[:since]
        "since #{'yesterday ' if started.to_date < today}#{clock(started)}"
      end

      def banner_next
        change = next_change
        return { label: 'No outages' } unless change

        left = countdown(change[:until] - now)
        if change[:state] == :off
          { label: "Back at #{clock(change[:until])}", value: left, sub: "#{outage_pct.round}% of outage passed" }
        else
          { label: "Next off #{clock(change[:until])}", value: left, sub: 'hours : minutes' }
        end
      end

      # How much of the scheduled outage in progress has passed, 0–100
      def outage_pct
        change = next_change
        ((now - change[:from]) * 100.0 / (change[:until] - change[:from])).clamp(0, 100).round(1)
      end

      def planned_segments
        @schedule.outages(today).map { |from, to| { from: from, to: to, css: 'plan' } } +
          @schedule.possible(today).map { |from, to| { from: from, to: to, css: 'maybe' } }
      end

      def schedule_note(plan)
        if !@schedule.known?(today) then 'no schedule yet'
        elsif plan.empty? then 'no outages'
        end
      end
    end
  end
end
