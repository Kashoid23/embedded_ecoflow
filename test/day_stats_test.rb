# frozen_string_literal: true

require 'test_helper'

class DayStatsTest < Minitest::Test
  DATE = Date.new(2026, 11, 26)
  MIDNIGHT = Time.new(2026, 11, 26).to_i

  # Samples every minute from `from` to `to` (minutes), one station
  def samples(from, to, grid:, out: 60, sn: 'A')
    (from...to).map { |m| { 't' => MIDNIGHT + m * 60, 'sn' => sn, 'out' => out, 'grid' => grid } }
  end

  def build(rows, now: Time.at(MIDNIGHT + 86_400))
    EcoflowDashboard::DayStats.build(rows, date: DATE, now: now, interval: 60)
  end

  def test_outage_minutes_and_segments
    stats = build(samples(0, 60, grid: true) + samples(60, 90, grid: false) + samples(90, 120, grid: true))

    assert_in_delta 30, stats.off_minutes
    assert_equal(%i[on off on], stats.segments.map { |s| s[:state] })
    assert_equal [60.0, 90.0], stats.segments[1].values_at(:from, :to)
  end

  def test_energy_is_power_times_time
    stats = build(samples(0, 61, grid: true, out: 120)) # 60 one-minute intervals at 120 W

    assert_in_delta 120, stats.consumed_wh # 120 W × 1 h
  end

  def test_gaps_are_not_counted
    stats = build(samples(0, 10, grid: false) + samples(100, 110, grid: false))

    assert_in_delta 20, stats.off_minutes
    assert_equal 2, stats.segments.size
  end

  def test_grid_is_on_if_any_station_sees_it
    stats = build(samples(0, 10, grid: false, sn: 'A') + samples(0, 10, grid: true, sn: 'B'))

    assert_equal 0, stats.off_minutes
  end

  def test_no_samples
    assert_predicate build([]), :no_data?
  end
end
