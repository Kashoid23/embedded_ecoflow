# frozen_string_literal: true

require_relative 'test_helper'

class BatteryTrendTest < Minitest::Test
  include TestSupport
  include EcoflowDashboard

  def setup
    @trend = BatteryTrend.new
  end

  def falling?(soc, sn: 'A') = @trend.falling?(sn, BatteryTrend::KEY => soc)

  def test_falling_charge
    refute falling?(99.0)
    refute falling?(98.9) # jitter
    assert falling?(98.6)
    assert falling?(98.6) # holds while the reading doesn't move
    assert falling?(98.4)
  end

  def test_rising_charge_ends_it
    falling?(99.0)
    falling?(98.5)
    assert falling?(98.7) # small rebound
    refute falling?(98.9)
  end

  def test_per_station
    falling?(99.0)
    assert falling?(98.0)
    refute falling?(50.0, sn: 'B')
  end

  def test_expires_when_the_charge_stops_falling
    t = NOW
    @trend.falling?('A', { BatteryTrend::KEY => 100.0 }, t)
    assert @trend.falling?('A', { BatteryTrend::KEY => 99.6 }, t + 60) # drift on the grid at the charge limit
    assert @trend.falling?('A', { BatteryTrend::KEY => 99.6 }, t + 60 + BatteryTrend::HOLD)
    refute @trend.falling?('A', { BatteryTrend::KEY => 99.6 }, t + 120 + BatteryTrend::HOLD)
    assert @trend.falling?('A', { BatteryTrend::KEY => 99.2 }, t + 180 + BatteryTrend::HOLD) # falls again
  end

  def test_without_the_reading
    refute @trend.falling?('A', {})
  end

  # The live outage of 26.11.2026: inverter readings frozen on grid, battery module still reporting
  def test_overrides_frozen_grid_readings_in_sampler
    @tmp = Dir.mktmpdir
    client = FakeClient.new
    store = SampleStore.new(File.join(@tmp, 'samples'))
    sampler = Sampler.new(client: client, store: store, settings: settings)

    client.soc = 99.0
    sampler.tick(NOW)
    assert store.read(NOW.to_date).first['grid']

    client.soc = 98.49
    sampler.tick(NOW + 60)
    refute store.read(NOW.to_date).last['grid']
    refute sampler.devices.first.grid
  end
end
