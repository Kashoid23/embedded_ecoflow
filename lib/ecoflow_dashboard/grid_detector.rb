# frozen_string_literal: true

module EcoflowDashboard
  # Decides from a station's quota values whether grid power reaches its AC input.
  #
  # First the battery: while it drains (discharge timer below 5999 min) the station runs from it,
  # so there is no grid, whatever the voltages say. Every model reports this timer.
  #
  # Grid present when the AC output is passing the grid through: the output voltage follows the
  # input voltage (213 V in, 213.6 V out) instead of the inverter's own setpoint (230 V). This
  # works while nothing flows, e.g. battery full and nothing plugged in.
  # Not yet confirmed against a real outage: if it misjudges, compare the ac_in_v / ac_out_v
  # fields in the samples from before and during one.
  #
  # Otherwise every signal the station reports must agree:
  #   - AC input voltage above 100 V. Not enough on its own: DELTA 2 Max keeps reporting
  #     a high value during an outage.
  #   - Total input power (pd.wattsInSum) above 10 W. With the grid present the station's load
  #     runs through its input (bypass), so 0 W means no grid when the pass-through check
  #     can't decide (no output readings, or grid voltage right at the setpoint).
  #
  # Stations reporting none of these (RIVER 2 Pro) fall back to inv.inputWatts, their AC input,
  # trusted only once the discharge timer says the battery isn't draining: on DELTA 2 Max it is the
  # inverter's own input, which is the battery during an outage. Nothing flowing either way
  # (no load, full battery) is unknown, not "no grid".
  class GridDetector
    VOLTAGE_KEY = 'inv.acInVol'
    POWER_KEY   = 'pd.wattsInSum'
    FREQ_KEY    = 'inv.acInFreq'
    OUT_VOLTAGE_KEY = 'inv.invOutVol'
    SETPOINT_KEY    = 'inv.cfgAcOutVol' # the voltage the inverter makes on battery
    INV_INPUT_KEY   = 'inv.inputWatts'
    # Battery time left in minutes, documented for DELTA 2 Max and RIVER 2 Pro. Not pd.remainTime:
    # that one is signed (> 0 until full, < 0 until empty) and RIVER 2 Pro doesn't report it.
    DISCHARGE_KEY   = 'bms_emsStatus.dsgRemainTime'
    KEYS = [VOLTAGE_KEY, POWER_KEY, FREQ_KEY, OUT_VOLTAGE_KEY, SETPOINT_KEY, INV_INPUT_KEY,
            DISCHARGE_KEY].freeze

    MIN_VOLTS  = 100 # below this it's noise or a residual reading, not the grid
    MIN_WATTS  = 10
    SAME_VOLTS = 3 # output within this of the input follows it; within this of the setpoint, it's the inverter
    NOT_DISCHARGING = 5999 # discharge timer value while the battery isn't draining

    # true / false, or nil when it can't be told.
    # falling: true when the battery charge is falling (BatteryTrend), which outranks every reading here:
    # the inverter readings can freeze during an outage.
    def self.grid?(data, falling = false)
      timer = data[DISCHARGE_KEY]
      return false if falling || (timer && draining?(timer))
      return true if passing_through?(data)

      v = volts(data)
      w = watts(data)
      checks = []
      checks << (v >= MIN_VOLTS) if v
      checks << (w >= MIN_WATTS) if w
      return checks.all? unless checks.empty?

      # No voltage or pd.wattsInSum (RIVER 2 Pro): power on the AC input counts only once the timer
      # has ruled the battery out; nothing flowing is unknown
      true if timer && data[INV_INPUT_KEY].to_f >= MIN_WATTS
    end

    # A discharge timer value (minutes) that means the battery is draining
    def self.draining?(minutes) = minutes.to_i.between?(1, NOT_DISCHARGING - 1)

    def self.watts(data)
      data[POWER_KEY]&.to_f
    end

    # The AC output follows the grid's voltage, not the inverter's setpoint
    def self.passing_through?(data)
      input  = volts(data)
      output = mv_to_v(data[OUT_VOLTAGE_KEY])
      setpoint = mv_to_v(data[SETPOINT_KEY])
      return false unless input && output && setpoint && input >= MIN_VOLTS

      (output - input).abs <= SAME_VOLTS && (output - setpoint).abs > SAME_VOLTS
    end

    # AC input voltage in volts
    def self.volts(data) = mv_to_v(data[VOLTAGE_KEY])

    # EcoFlow reports volts as millivolts: 230000 = 230 V
    def self.mv_to_v(mv) = mv && mv.to_f / 1000.0

    # Raw AC readings stored in each sample, to check the pass-through rule against a real outage.
    # Only the readings the station reports, so models without them don't fill the files with nulls.
    def self.readings(data)
      { ac_in_v: volts(data), ac_in_hz: data[FREQ_KEY], ac_out_v: mv_to_v(data[OUT_VOLTAGE_KEY]) }.compact
    end
  end
end
