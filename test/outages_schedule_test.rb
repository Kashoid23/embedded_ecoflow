# frozen_string_literal: true

require 'test_helper'

class OutagesScheduleTest < Minitest::Test
  TODAY = Date.new(2026, 11, 26)

  def setup
    @schedule = EcoflowDashboard::Outages::Schedule.new
    @schedule.replace(
      TODAY => [[480, 750, :definite], [750, 780, :possible], [960, 1200, :definite]]
    )
  end

  def test_outages_and_planned_minutes
    assert_equal [[480, 750], [960, 1200]], @schedule.outages(TODAY)
    assert_equal [[750, 780]], @schedule.possible(TODAY)
    assert_equal 510, @schedule.planned_minutes(TODAY) # possible outages aren't counted
  end

  def test_unknown_day
    refute @schedule.known?(TODAY + 1)
    assert_empty @schedule.outages(TODAY + 1)
  end

  def test_next_change_before_outage
    change = @schedule.next_change(Time.new(2026, 11, 26, 7, 0))

    assert_equal :on, change[:state]
    assert_equal Time.new(2026, 11, 26, 8, 0), change[:until]
  end

  def test_next_change_during_outage
    change = @schedule.next_change(Time.new(2026, 11, 26, 17, 0))

    assert_equal :off, change[:state]
    assert_equal Time.new(2026, 11, 26, 16, 0), change[:from]
    assert_equal Time.new(2026, 11, 26, 20, 0), change[:until]
  end

  def test_next_change_looks_at_tomorrow
    @schedule.replace(TODAY => [], TODAY + 1 => [[120, 240, :definite]])
    change = @schedule.next_change(Time.new(2026, 11, 26, 21, 0))

    assert_equal Time.new(2026, 11, 27, 2, 0), change[:until]
  end

  def test_nothing_planned
    assert_nil @schedule.next_change(Time.new(2026, 11, 26, 21, 0))
  end

  def test_outage_across_midnight_ends_tomorrow
    @schedule.replace(TODAY => [[1320, 1440, :definite]], TODAY + 1 => [[0, 120, :definite]])
    change = @schedule.next_change(Time.new(2026, 11, 26, 23, 0))

    assert_equal :off, change[:state]
    assert_equal Time.new(2026, 11, 26, 22, 0), change[:from]
    assert_equal Time.new(2026, 11, 27, 2, 0), change[:until]
  end
end
