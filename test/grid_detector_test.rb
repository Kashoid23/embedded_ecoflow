# frozen_string_literal: true

require 'test_helper'

class GridDetectorTest < Minitest::Test
  Detector = EcoflowDashboard::GridDetector

  def test_grid_with_voltage_and_input_power
    assert Detector.grid?('inv.acInVol' => 231_000, 'pd.wattsInSum' => 95)
    assert_in_delta 231, Detector.volts('inv.acInVol' => 231_000)
  end

  def test_voltage_without_input_power_is_not_grid
    # DELTA 2 Max during an outage: voltage and inverter input stay high, nothing flows in
    refute Detector.grid?('inv.acInVol' => 230_000, 'inv.inputWatts' => 95, 'pd.wattsInSum' => 0)
  end

  def test_voltage_only_station
    assert Detector.grid?('inv.acInVol' => 229_000)
    refute Detector.grid?('inv.acInVol' => 0)
  end

  def test_residual_voltage_is_not_grid
    refute Detector.grid?('inv.acInVol' => 850, 'inv.inputWatts' => 0)
    refute Detector.grid?('inv.acInVol' => 12_000)
  end

  def test_power_fallback_without_voltage
    assert Detector.grid?('pd.wattsInSum' => 350)
    refute Detector.grid?('pd.wattsInSum' => 3)
    assert_nil Detector.grid?('inv.inputWatts' => 350) # inverter input says nothing about the grid
  end

  # DELTA 2 Max on grid, battery full, nothing plugged in (live readings, 26.11.2026):
  # nothing flows in, but the AC output follows the grid's 213 V instead of its own 230 V
  IDLE_ON_GRID = { 'inv.acInVol' => 213_000, 'inv.invOutVol' => 213_639, 'inv.cfgAcOutVol' => 230_000,
                   'pd.wattsInSum' => 0 }.freeze

  def test_idle_station_passing_grid_through
    assert Detector.grid?(IDLE_ON_GRID)
  end

  def test_inverter_making_its_own_voltage_is_not_grid
    # Outage: the input still shows the last grid voltage, the inverter outputs its 230 V setpoint
    refute Detector.grid?(IDLE_ON_GRID.merge('inv.invOutVol' => 229_800))
  end

  def test_grid_at_setpoint_voltage_falls_back_to_input_power
    # Grid at exactly 230 V can't be told from the inverter by voltage: input power decides
    at_setpoint = IDLE_ON_GRID.merge('inv.acInVol' => 230_000, 'inv.invOutVol' => 230_400)
    refute Detector.grid?(at_setpoint)
    assert Detector.grid?(at_setpoint.merge('pd.wattsInSum' => 80))
  end

  def test_draining_battery_is_not_grid
    # Whatever the voltages say: the battery feeds the load
    refute Detector.grid?(IDLE_ON_GRID.merge('bms_emsStatus.dsgRemainTime' => 340))
    refute Detector.grid?('pd.wattsInSum' => 95, 'bms_emsStatus.dsgRemainTime' => 125)
    assert Detector.grid?('pd.wattsInSum' => 95, 'bms_emsStatus.dsgRemainTime' => 5999)
  end

  def test_signed_pd_remain_time_is_ignored
    # pd.remainTime > 0 is the time until full, i.e. charging, not draining
    assert Detector.grid?('pd.wattsInSum' => 95, 'pd.remainTime' => 125)
  end

  # RIVER 2 Pro on grid, 40 W load (live readings, 26.11.2026): no voltage or pd.wattsInSum,
  # its AC input carries the load while the battery isn't draining
  RIVER_ON_GRID = { 'inv.inputWatts' => 40, 'inv.outputWatts' => 40, 'pd.wattsOutSum' => 40,
                    'bms_emsStatus.dsgRemainTime' => 5999 }.freeze

  def test_river_on_grid
    assert Detector.grid?(RIVER_ON_GRID)
  end

  def test_river_on_battery
    refute Detector.grid?(RIVER_ON_GRID.merge('inv.inputWatts' => 0, 'bms_emsStatus.dsgRemainTime' => 480))
  end

  def test_river_idle_is_unknown
    # Nothing flows in or out: grid or not, the readings look the same
    assert_nil Detector.grid?(RIVER_ON_GRID.merge('inv.inputWatts' => 0, 'pd.wattsOutSum' => 0))
  end

  def test_unknown_without_values
    assert_nil Detector.grid?({})
  end
end
