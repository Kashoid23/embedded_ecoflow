# frozen_string_literal: true

module EcoflowDashboard
  # Watches each station's battery charge from its battery management system.
  #
  # During an outage the cloud can keep serving the station's last inverter readings (grid
  # voltage, input power, discharge timer) for as long as it is out, while the battery module still
  # reports a charge that keeps falling. A charge that fell by STEP is the battery feeding the
  # load, so no grid, whatever the frozen readings say.
  #
  # It holds until the charge rises by STEP, or until it has not fallen by another STEP for HOLD
  # seconds: a battery feeding a load keeps falling, while one sitting on the grid at its charge
  # limit can drift down a step (self-discharge, recalibration) and then stay put.
  class BatteryTrend
    KEY  = 'bms_bmsStatus.f32ShowSoc' # %, with decimals; DELTA 2 Max reports it, RIVER 2 Pro doesn't
    STEP = 0.3 # % — ignores rounding jitter; about 6 Wh on a 2 kWh battery
    HOLD = 30 * 60 # s — a 2 kWh battery falls a STEP in this time at any load above ~12 W

    def initialize
      @mutex   = Mutex.new
      @ref     = {} # sn => charge at the last change of direction
      @falling = {} # sn => time of the last fall by STEP, while falling
    end

    # true when the station's battery charge is falling, false otherwise (also without the reading)
    def falling?(sn, data, now = Time.now)
      soc = data[KEY]&.to_f
      return false unless soc

      @mutex.synchronize do
        ref = @ref[sn] ||= soc
        if (soc - ref).abs >= STEP
          soc < ref ? @falling[sn] = now : @falling.delete(sn)
          @ref[sn] = soc
        end
        since = @falling[sn]
        !since.nil? && now - since <= HOLD
      end
    end
  end
end
