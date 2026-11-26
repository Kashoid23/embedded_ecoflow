# frozen_string_literal: true

require 'test_helper'

class OblenergoSourceTest < Minitest::Test
  # Real data from OE_OUTAGE_DATA, 26.11.2026
  FIXTURE = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'oblenergo.json')))
  DATE = Date.new(2026, 11, 26)

  def parse(group, json = FIXTURE)
    EcoflowDashboard::Outages::OblenergoSource.new(region: 'Exampleoblenergo', group: group).parse(json)
  end

  def test_converts_hours_to_merged_slots
    # hours 7–9, 14–16, 20–21 are "no"  ->  06:00–09:00, 13:00–16:00, 19:00–21:00
    assert_equal [[360, 540, :definite], [780, 960, :definite], [1140, 1260, :definite]], parse('1.1').fetch(DATE)
  end

  def test_half_hours_and_possible_outages
    json = { 'fact' => { 'data' => { '1795644000' => {
      'GPV2.1' => { '1' => 'first', '2' => 'second', '3' => 'no', '4' => 'mfirst', '5' => 'yes' }
    } } } }
    assert_equal [[0, 30, :definite], [90, 180, :definite], [180, 210, :possible]], parse('2.1', json).fetch(DATE)
  end

  def test_unknown_group_gives_no_days
    assert_empty parse('9.9')
  end

  def test_works_with_schedule_store
    schedule = EcoflowDashboard::Outages::Schedule.new
    schedule.replace(parse('1.1'))

    assert_equal 480, schedule.planned_minutes(DATE) # 3 h + 3 h + 2 h
    assert_equal :on, schedule.next_change(Time.new(2026, 11, 26, 10, 0))[:state]
  end
end
