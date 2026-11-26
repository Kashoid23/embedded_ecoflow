# frozen_string_literal: true

module EcoflowDashboard
  # Decides from a station's live values whether grid power reaches its AC input, using only
  # readings that say directly what flows right now — no voltage comparisons, no trends over time.
  #
  # In order, the first that answers wins:
  #   1. The battery gives power (bms_bmsStatus.outputWatts >= 10 W): no grid. Measured by the
  #      battery itself; on grid it stays at 0–3 W, the load runs past it (bypass).
  #   2. Power on the AC input (inv.inputWatts >= 5 W): grid. With the grid present the load runs
  #      through it, and a charging battery adds to it.
  #   3. A load on the output (pd.wattsOutSum >= 5 W) with nothing on the AC input: the battery
  #      feeds it, no grid.
  #   4. Nothing flowing either way (no load, full battery): unknown.
  #
  # The same three readings on every station (DELTA 2 Max and RIVER 2 Pro both send them over MQTT).
  # inv.inputWatts is the AC input alone, so solar never counts as grid. Only the live values are
  # right (see Ecoflow::Stream).
  # Not yet seen during an outage on DELTA 2 Max: the samples keep pd.wattsInSum next to it to compare.
  #
  # Not used: AC input voltage (DELTA 2 Max keeps reporting the last grid voltage during an outage)
  # and the discharge timer (a forecast, not a measurement).
  class GridDetector
    AC_IN_KEY       = 'inv.inputWatts'
    OUT_KEY         = 'pd.wattsOutSum'
    BATTERY_OUT_KEY = 'bms_bmsStatus.outputWatts'
    TOTAL_IN_KEY    = 'pd.wattsInSum' # all inputs; only stored, to compare with the AC input in an outage
    KEYS = [AC_IN_KEY, OUT_KEY, BATTERY_OUT_KEY, TOTAL_IN_KEY].freeze

    # Input and output: 0 or a real load (20 W and up on 26.11.2026), nothing in between;
    # 5 W still catches a small load such as a router
    MIN_WATTS = 5
    # The battery reports 0–3 W while it isn't feeding anything; feeding the load it gives at least that load
    MIN_BATTERY_WATTS = 10

    # true / false, or nil when it can't be told
    def self.grid?(data)
      return false if data[BATTERY_OUT_KEY].to_f >= MIN_BATTERY_WATTS

      input = watts(data)
      return true if input && input >= MIN_WATTS

      false if data[OUT_KEY].to_f >= MIN_WATTS
    end

    # Power on the AC input, W; nil when the station doesn't report it
    def self.watts(data) = data[AC_IN_KEY]&.to_f

    # Raw readings stored in each sample, to check the decision against a real outage.
    # Only the readings the station reports, so models without them don't fill the files with nulls.
    def self.readings(data)
      { bat: data[BATTERY_OUT_KEY], in_sum: data[TOTAL_IN_KEY] }.compact
    end
  end
end
