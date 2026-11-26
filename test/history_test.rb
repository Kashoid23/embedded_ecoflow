# frozen_string_literal: true

require 'test_helper'

class HistoryTest < Minitest::Test
  include TestSupport
  include EcoflowDashboard

  def setup
    @tmp     = Dir.mktmpdir
    @store   = SampleStore.new(@tmp)
    @history = History.new(store: @store, interval: 60)
  end

  # One sample a minute, 60 W out. N samples = N minutes of grid state and N-1 minutes of energy.
  def record(start, minutes, grid:)
    minutes.times { |m| @store.append(start + m * 60, [{ sn: 'A', out: 60, grid: grid }]) }
  end

  def test_month_adds_up_every_day_of_this_month
    record(Time.new(2026, 10, 31, 10, 0), 60, grid: false) # last month: not counted
    record(Time.new(2026, 11, 1, 10, 0), 60, grid: false)  # 60 min off, 59 Wh
    record(Time.new(2026, 11, 25, 10, 0), 30, grid: false) # 30 min off, 29 Wh
    record(Time.new(2026, 11, 26, 10, 0), 61, grid: true)  # today: 60 Wh, no outage

    month = @history.month(NOW)

    assert_in_delta 90, month.off_minutes
    assert_in_delta 148, month.consumed_wh
    assert_in_delta 0, @history.day(NOW.to_date, now: NOW).off_minutes
  end

  def test_past_days_are_read_once
    record(Time.new(2026, 11, 25, 10, 0), 30, grid: false)
    @history.month(NOW)

    FileUtils.rm_rf(Dir[File.join(@tmp, '*')]) # past days come from memory now

    assert_in_delta 30, @history.month(NOW).off_minutes
  end

  def test_empty_month
    month = @history.month(NOW)

    assert_equal 0, month.off_minutes
    assert_equal 0, month.consumed_wh
  end

  def test_yesterday_is_not_kept_until_its_last_tick_has_landed
    yesterday = NOW.to_date - 1
    just_after_midnight = Time.new(2026, 11, 26, 0, 0, 1)
    record(Time.new(2026, 11, 25, 10, 0), 30, grid: false)
    @history.day(yesterday, now: just_after_midnight)

    @store.append(Time.new(2026, 11, 25, 23, 59, 55), [{ sn: 'A', out: 60, grid: false }]) # late tick

    assert_in_delta 30 + 5 / 60.0, @history.day(yesterday, now: NOW).off_minutes # 5 s to midnight
  end
end
