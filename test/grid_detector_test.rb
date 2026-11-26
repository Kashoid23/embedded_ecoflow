# frozen_string_literal: true

require 'test_helper'

class GridDetectorTest < Minitest::Test
  Detector = EcoflowDashboard::GridDetector

  # Live MQTT values, 26.11.2026, both on grid with the load passing through
  DELTA_ON_GRID = { 'inv.inputWatts' => 79, 'pd.wattsOutSum' => 78, 'bms_bmsStatus.outputWatts' => 0,
                    'pd.wattsInSum' => 78 }.freeze
  RIVER_ON_GRID = { 'inv.inputWatts' => 40, 'pd.wattsOutSum' => 40, 'bms_bmsStatus.outputWatts' => 2 }.freeze

  def test_power_on_the_ac_input_is_grid
    assert Detector.grid?(DELTA_ON_GRID)
    assert Detector.grid?(RIVER_ON_GRID)
    assert Detector.grid?(DELTA_ON_GRID.merge('inv.inputWatts' => 589, 'pd.wattsOutSum' => 82)) # charging
  end

  def test_load_with_nothing_on_the_ac_input_is_battery
    refute Detector.grid?(DELTA_ON_GRID.merge('inv.inputWatts' => 0))
    refute Detector.grid?(RIVER_ON_GRID.merge('inv.inputWatts' => 0))
  end

  def test_battery_giving_power_is_not_grid
    # Measured by the battery itself, whatever the input says
    refute Detector.grid?(DELTA_ON_GRID.merge('bms_bmsStatus.outputWatts' => 85))
  end

  def test_battery_trickle_on_grid_is_still_grid
    assert Detector.grid?(RIVER_ON_GRID.merge('bms_bmsStatus.outputWatts' => 9))
  end

  def test_solar_is_not_grid
    # pd.wattsInSum counts every input; only the AC input means grid
    refute Detector.grid?(DELTA_ON_GRID.merge('inv.inputWatts' => 0, 'pd.wattsInSum' => 200))
  end

  def test_small_load
    # A router alone: 6 W through the AC input on grid, from the battery in an outage
    assert Detector.grid?('inv.inputWatts' => 6, 'pd.wattsOutSum' => 6, 'bms_bmsStatus.outputWatts' => 0)
    refute Detector.grid?('inv.inputWatts' => 0, 'pd.wattsOutSum' => 6, 'bms_bmsStatus.outputWatts' => 7)
  end

  def test_trickle_below_threshold_is_nothing
    assert_nil Detector.grid?('inv.inputWatts' => 3, 'pd.wattsOutSum' => 4)
  end

  def test_voltage_and_timer_decide_nothing
    assert_nil Detector.grid?('inv.acInVol' => 230_000)
    assert Detector.grid?(DELTA_ON_GRID.merge('bms_emsStatus.dsgRemainTime' => 125))
  end

  def test_idle_station_is_unknown
    # Nothing flows in or out: grid or not, the readings look the same
    assert_nil Detector.grid?(RIVER_ON_GRID.merge('inv.inputWatts' => 0, 'pd.wattsOutSum' => 0,
                                                  'bms_bmsStatus.outputWatts' => 0))
  end

  def test_unknown_without_values
    assert_nil Detector.grid?({})
  end

  def test_readings_for_the_samples
    assert_equal({ bat: 0, in_sum: 78 }, Detector.readings(DELTA_ON_GRID))
    assert_equal({ bat: 2 }, Detector.readings(RIVER_ON_GRID))
  end
end
