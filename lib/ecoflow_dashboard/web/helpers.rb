# frozen_string_literal: true

module EcoflowDashboard
  module Web
    # Formatting helpers available in every template.
    module Helpers
      # How a quota value is shown: a unit suffix, or a lambda (called with the helpers as self)
      FORMATS = {
        'pd.soc' => '%',
        'pd.wattsInSum' => 'W',
        'pd.wattsOutSum' => 'W',
        'bms_bmsStatus.temp' => '°C',
        'inv.inputWatts' => 'W',
        'inv.outputWatts' => 'W',
        'mppt.inWatts' => 'W',
        'inv.acInVol' => ->(mv) { "#{GridDetector.mv_to_v(mv).round} V" },
        GridDetector::DISCHARGE_KEY => ->(minutes) { remaining(minutes) }
      }.freeze

      def format_value(key, value)
        return '—' if value.nil?

        format = FORMATS[key]
        return instance_exec(value, &format) if format.is_a?(Proc)

        text = value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value.to_s
        [text, format].compact.join(' ')
      end

      # A station's quota value, formatted with its unit
      def quota(device, key) = format_value(key, device.values[key])

      def remaining(minutes)
        GridDetector.draining?(minutes) ? short_duration(minutes) : '—'
      end

      # "1h 50m", "6h 00m"
      def short_duration(minutes)
        hours, rest = minutes.round.divmod(60)
        format('%dh %02dm', hours, rest)
      end

      # Seconds to go -> "3:39" (hours:minutes, rounded up so it never reads 0:00 early)
      def countdown(seconds)
        hours, rest = (seconds / 60.0).ceil.clamp(0..).divmod(60)
        format('%d:%02d', hours, rest)
      end

      # Charge bar tone by level (CSS class, coloured by the theme)
      def soc_tone(soc)
        if soc > 50 then 'ok'
        elsif soc >= 20 then 'warn'
        else 'bad'
        end
      end

      def kwh(wh) = format('%.2f kWh', wh / 1000.0)

      def energy(wh)
        wh >= 1000 ? kwh(wh) : format('%d Wh', wh.round)
      end

      # Minutes since midnight -> percent of the day, for CSS positions
      def day_pct(minutes) = format('%.2f', minutes / 14.4)

      # Time -> "14:30"
      def clock(time) = time.strftime('%H:%M')

      # Minutes since midnight -> "14:30"
      def hhmm(minutes)
        minutes = minutes.round
        format('%02d:%02d', (minutes / 60) % 24, minutes % 60)
      end
    end
  end
end
