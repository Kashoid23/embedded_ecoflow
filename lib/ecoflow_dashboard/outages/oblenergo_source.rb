# frozen_string_literal: true

module EcoflowDashboard
  module Outages
    Error = Class.new(EcoflowDashboard::Error)

    # Regional oblenergo schedules from the community
    # project github.com/yaroslav2901/OE_OUTAGE_DATA, which parses the official oblenergo
    # sites every few minutes. Not an official API.
    #
    #   { "fact" => { "data" => { "1795644000" => { "GPV3.1" => { "1" => "yes", "2" => "no", ... } } } } }
    #
    # The day key is the Unix time of midnight in Kyiv. Hour "1" is 00:00–01:00, "24" is 23:00–24:00.
    # Values: yes — power; no — no power; first / second — no power in the first / second
    # half of the hour; mfirst / msecond — possible outage in that half.
    class OblenergoSource
      URL = 'https://raw.githubusercontent.com/yaroslav2901/OE_OUTAGE_DATA/main/data/%s.json'

      # value => [[offset_from, offset_to, type], ...] within the hour, in minutes
      HOUR_PARTS = {
        'no' => [[0, 60, :definite]],
        'first' => [[0, 30, :definite]],
        'second' => [[30, 60, :definite]],
        'maybe' => [[0, 60, :possible]],
        'mfirst' => [[0, 30, :possible]],
        'msecond' => [[30, 60, :possible]]
      }.freeze

      def initialize(region:, group:)
        @uri   = URI(format(URL, region))
        @group = "GPV#{group}"
      end

      # { Date => [[from, to, type], ...] }
      def fetch = parse(HttpJson.get(@uri, error: Error))

      def parse(json)
        json.dig('fact', 'data').to_h.filter_map do |midnight, groups|
          hours = groups[@group] or next
          [kyiv_date(midnight.to_i), slots(hours)]
        end.to_h
      end

      private

      # Kyiv midnight is 21:00 or 22:00 UTC of the previous day; +12 h lands safely inside the
      # right day whatever the server's time zone is.
      def kyiv_date(timestamp) = Time.at(timestamp + 12 * 3600).utc.to_date

      def slots(hours)
        parts = hours.flat_map do |hour, value|
          start = (hour.to_i - 1) * 60
          HOUR_PARTS.fetch(value, []).map { |from, to, type| [start + from, start + to, type] }
        end
        merge(parts.sort_by(&:first))
      end

      # Joins touching ranges of the same type: 06:00–07:00 + 07:00–08:00 -> 06:00–08:00
      def merge(parts)
        parts.each_with_object([]) do |(from, to, type), out|
          if out.last && out.last[2] == type && out.last[1] == from
            out.last[1] = to
          else
            out << [from, to, type]
          end
        end
      end
    end
  end
end
