# frozen_string_literal: true

module EcoflowDashboard
  # Current weather from Open-Meteo (open-meteo.com: free, no API key).
  module Weather
    Error = Class.new(EcoflowDashboard::Error)

    # temp in °C, code — WMO weather code, day — false at night
    Report = Data.define(:temp, :code, :day)

    # Reopened rather than given as a Data.define block, so KINDS is Report::KINDS
    class Report
      # WMO code -> icon kind
      KINDS = {
        clear: [0],
        partly: [1, 2],
        cloudy: [3],
        fog: [45, 48],
        rain: [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82], # drizzle, rain, showers
        snow: [71, 73, 75, 77, 85, 86],
        thunder: [95, 96, 99]
      }.flat_map { |kind, codes| codes.map { |c| [c, kind] } }.to_h.freeze

      def kind = KINDS.fetch(code, :cloudy)
    end

    # Current weather at the given coordinates from Open-Meteo (free, no API key)
    class OpenMeteoSource
      URL = 'https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s' \
            '&current=temperature_2m,weather_code,is_day'

      def initialize(lat:, lon:)
        @uri = URI(format(URL, lat, lon))
      end

      def fetch = parse(HttpJson.get(@uri, error: Error))

      def parse(json)
        now  = json['current'] if json.is_a?(Hash)
        temp = now['temperature_2m'] if now.is_a?(Hash)
        # Without a temperature there is nothing to show; keep the last report instead
        raise Error, 'open-meteo: no current temperature in the response' unless temp.is_a?(Numeric)

        Report.new(temp: temp, code: now['weather_code'].to_i, day: now['is_day'].to_i == 1)
      end
    end
  end
end
