# frozen_string_literal: true

require 'test_helper'

class DashboardTest < Minitest::Test
  include TestSupport
  include EcoflowDashboard

  TODAY = NOW.to_date

  def setup
    @tmp      = Dir.mktmpdir
    @store    = SampleStore.new(@tmp)
    @schedule = Outages::Schedule.new
  end

  def dashboard(env = { 'OUTAGE_GROUP' => '1.1' }, devices: [])
    s = settings(env)
    Web::Dashboard.new(now: NOW, devices: devices, schedule: @schedule, settings: s,
                       history: History.new(store: @store, interval: s.sample_interval))
  end

  def no_power_since(minute)
    (minute..720).each { |m| @store.append(Time.new(2026, 11, 26) + m * 60, [{ sn: 'A', out: 50, grid: false }]) }
  end

  def power_on_since(minute)
    (minute..720).each { |m| @store.append(Time.new(2026, 11, 26) + m * 60, [{ sn: 'A', out: 50, grid: true }]) }
  end

  def station(soc:, out:, name: 'DELTA 2 Max', error: nil, **values)
    Sampler::Device.from_api({ 'productName' => name, 'online' => 1 }, 'A')
                   .with(values: { 'pd.soc' => soc, 'pd.wattsOutSum' => out, **values }, error: error)
  end

  def test_planned_outage_counts_down_to_power_back
    @schedule.replace({ TODAY => [[600, 960, :definite]] }) # 10:00–16:00
    no_power_since(600)

    banner = dashboard.banner

    assert_equal ['No power', :bad], banner.values_at(:title, :tone)
    assert_equal 'since 10:00', banner[:detail]
    assert_equal({ label: 'Back at 16:00', value: '4:00', icon: :hourglass }, banner[:next])
    assert_equal 33.3, banner[:progress] # 2 h of 6 h
  end

  def test_power_on_counts_down_to_next_outage_tomorrow
    @schedule.replace({ TODAY + 1 => [[480, 600, :definite]] })
    power_on_since(0)

    banner = dashboard.banner

    assert_nil banner[:detail] # no "since" while the power is on
    assert_equal({ label: 'Next off 08:00', value: '20:00', icon: :hourglass }, banner[:next])
    assert_nil banner[:progress]
  end

  # The schedule says off, the stations still see the grid: nothing to count down to
  def test_power_on_during_planned_outage_shows_no_countdown
    @schedule.replace({ TODAY => [[600, 960, :definite]] }) # 10:00–16:00
    power_on_since(0)

    banner = dashboard.banner

    assert_equal ['Power on', :ok], banner.values_at(:title, :tone)
    assert_equal({ label: 'Scheduled off', sub: '10:00–16:00' }, banner[:next])
    assert_nil banner[:progress]
  end

  def test_unplanned_outage_is_not_in_schedule
    @schedule.replace({ TODAY => [[900, 1020, :definite]] }) # 15:00–17:00, but power is already off
    no_power_since(600)

    banner = dashboard.banner

    assert_equal 'since 10:00', banner[:detail]
    assert_equal 'Next off 15:00', banner[:next][:label]
    assert_nil banner[:progress]
  end

  def test_no_outages_planned
    no_power_since(600)

    banner = dashboard({}).banner

    assert_equal 'since 10:00', banner[:detail] # no schedule: nothing to compare with
    assert_equal({ label: 'No outages' }, banner[:next])
  end

  def test_waiting_for_data_without_samples
    banner = dashboard({}).banner

    assert_equal ['Waiting for data', :muted], banner.values_at(:title, :tone)
    assert_nil banner[:progress]
  end

  # The grid station went idle at 11:00 (nothing in or out): power is still shown as on, the last known state
  def test_idle_grid_station_keeps_last_state
    (480...660).each { |m| @store.append(Time.new(2026, 11, 26) + m * 60, [{ sn: 'A', out: 50, grid: true }]) }
    (660..720).each { |m| @store.append(Time.new(2026, 11, 26) + m * 60, [{ sn: 'A', out: 0, grid: 'idle' }]) }
    banner = dashboard({}).banner

    assert_equal ['Power on', :ok], banner.values_at(:title, :tone)
    assert_equal Time.new(2026, 11, 26, 8), dashboard({}).current[:since]
  end

  # After a gap (e.g. a restart) the state carries on over idle samples only
  def test_idle_from_the_start_of_the_state
    (480...660).each { |m| @store.append(Time.new(2026, 11, 26) + m * 60, [{ sn: 'A', out: 50, grid: true }]) }
    (700..720).each { |m| @store.append(Time.new(2026, 11, 26) + m * 60, [{ sn: 'A', out: 0, grid: 'idle' }]) }

    assert_equal 'Power on', dashboard({}).banner[:title]
    assert_equal Time.new(2026, 11, 26, 11, 40), dashboard({}).current[:since]
  end

  def test_off_tile
    @schedule.replace({ TODAY => [[0, 360, :definite]] })
    no_power_since(610) # 10:10–12:00

    assert_equal({ label: 'Without power today', value: '1h 50m', tone: 'bad', sub: 'of 6h 00m' }, dashboard.off_tile)
    assert_nil dashboard({}).off_tile[:sub]
  end

  # The load counts only the stations that answered
  def test_consumed_tile
    page = dashboard(devices: [station(soc: 50, out: 30), station(soc: 100, out: 52, name: 'RIVER 2 Pro'),
                               station(soc: 90, out: 999, error: 'API 1006')])

    assert_equal({ label: 'Consumed today', value: '0 Wh', sub: 'now 82 W', sub_tone: 'accent' }, page.consumed_tile)
  end

  def test_station_without_live_data_yet
    waiting = station(soc: 0, out: 0).with(values: {})
    page    = dashboard(devices: [station(soc: 50, out: 30), waiting])

    assert_nil page.soc(waiting)
    assert_nil page.problem(waiting)
    assert_equal ['—', :muted], page.status(waiting)
    assert_equal 'now 30 W', page.consumed_tile[:sub]
  end

  def test_timeline_is_one_track_with_plan_and_actual
    @schedule.replace({ TODAY => [[600, 960, :definite], [1080, 1140, :possible]] })
    no_power_since(600)

    line = dashboard.timeline

    assert_equal(%w[plan maybe off], line[:segments].map { |s| s[:css] })
    assert_nil line[:note]
  end

  def test_empty_timeline_explains_why
    assert_equal 'no data yet · no schedule yet', dashboard.timeline[:note]
    assert_equal 'no data yet', dashboard({}).timeline[:note]
  end

  def test_outage_list_marks_each_by_time
    @schedule.replace({ TODAY => [[480, 600, :definite], [660, 780, :definite], [900, 1020, :definite],
                                  [1200, 1320, :definite]] })

    assert_equal(%i[past now next later], dashboard.outages_today.map { |o| o[:when] }) # 11:00–13:00 is on now
  end

  def test_formats
    page = dashboard

    assert_equal(['287 Wh', '1.42 kWh'], [287, 1420].map { |wh| page.energy(wh) })
    assert_equal(['1h 50m', '26h 00m'], [110, 1560].map { |m| page.short_duration(m) })
    assert_equal(['3:39', '0:01', '0:00'], [13_140, 1, -5].map { |s| page.countdown(s) })
  end

  def test_soc_tone
    page = dashboard

    assert_equal(%w[ok warn warn warn bad], [51, 50, 35, 20, 19].map { |s| page.soc_tone(s) })
  end

  def test_outage_since_yesterday_carries_over_midnight
    ((21 * 60 + 30)...1440).each do |m|
      @store.append(Time.new(2026, 11, 25) + m * 60, [{ sn: 'A', out: 50, grid: false }])
    end
    no_power_since(0)

    assert_equal 'since yesterday 21:30', dashboard({}).banner[:detail]
  end

  def test_right_after_midnight_uses_yesterdays_state
    ((21 * 60 + 30)...1440).each do |m|
      @store.append(Time.new(2026, 11, 25) + m * 60, [{ sn: 'A', out: 50, grid: false }])
    end
    s = settings({})
    page = Web::Dashboard.new(now: Time.new(2026, 11, 26, 0, 0, 30), devices: [], schedule: @schedule, settings: s,
                              history: History.new(store: @store, interval: s.sample_interval))

    assert_equal 'No power', page.banner[:title]
    assert_equal 'since yesterday 21:30', page.banner[:detail]
  end
end
