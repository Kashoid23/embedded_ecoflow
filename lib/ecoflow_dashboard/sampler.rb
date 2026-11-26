# frozen_string_literal: true

module EcoflowDashboard
  # Reads every station once per call to #tick: keeps the latest values in memory
  # (for the dashboard cards) and appends a sample per station to the SampleStore.
  # Values come from `source` (Ecoflow::Stream, the stations' live MQTT messages); the station
  # list from the HTTP client.
  class Sampler
    # grid: true/false whether this station runs from the grid, nil when it can't be told
    Device = Data.define(:sn, :name, :online, :values, :grid, :error) do
      def self.from_api(hash, sn)
        new(sn: sn, name: hash['productName'] || hash['deviceName'] || sn,
            online: hash['online'].to_i == 1, values: {}, grid: nil, error: nil)
      end
    end

    # Always requested: the stats and the station rows need them
    STAT_KEYS = %w[pd.soc pd.wattsOutSum].freeze

    # Remaining charge (mAh) and pack voltage (mV) from the battery management system, for the
    # backup estimate. Not every model reports them (RIVER 2 Pro doesn't); missing keys are just absent.
    BATTERY_KEYS = %w[bms_bmsStatus.remainCap bms_bmsStatus.vol].freeze

    # Battery time left in minutes, the station's own forecast: only shown
    TIME_LEFT_KEY = 'bms_emsStatus.dsgRemainTime'

    # Requested from every station
    POLL_KEYS = (STAT_KEYS + BATTERY_KEYS + GridDetector::KEYS + [TIME_LEFT_KEY]).uniq.freeze

    DEVICE_LIST_TTL = 3600

    def initialize(client:, source:, store:, settings:)
      @client   = client
      @source   = source
      @store    = store
      @settings = settings
      @mutex    = Mutex.new
      @devices  = []
    end

    def devices = @mutex.synchronize { @devices.dup }

    def tick(now = Time.now)
      refresh_device_list(now)

      updated = devices.map { |device| poll(device) } # in-memory reads, no round trips
      @mutex.synchronize { @devices = updated.map(&:first) }
      @store.append(now, updated.filter_map(&:last))
    end

    private

    # Returns [device_with_latest_values, sample_row_or_nil]
    # Never raises: a failure of one station must not lose the other stations' samples
    def poll(device)
      data = @source.quota(device.sn, POLL_KEYS)
      raise Ecoflow::Client::Error, "no quota data (#{data.class})" unless data.is_a?(Hash)

      grid_station = @settings.grid_station?(device.sn)
      grid = GridDetector.grid?(data)

      # Only grid stations decide whether the house has power, so only their rows carry grid
      row = { sn: device.sn, soc: data['pd.soc'], in: GridDetector.watts(data), out: data[GridDetector::OUT_KEY] }
      row.merge!(grid: grid.nil? ? DayStats::IDLE : grid, **GridDetector.readings(data)) if grid_station
      [device.with(values: data, grid: grid, error: nil), row]
    rescue StandardError => e
      message = e.is_a?(Ecoflow::Client::Error) ? e.message : "#{e.class}: #{e.message}"
      [device.with(error: message), nil]
    end

    def refresh_device_list(now)
      return if @listed_at && now - @listed_at < DEVICE_LIST_TTL

      from_api = @client.devices.to_h { |d| [d['sn'], d] }
      sns      = @settings.station_sns { from_api.keys }
      previous = devices.to_h { |d| [d.sn, d] }

      list = sns.map do |sn|
        fresh = Device.from_api(from_api.fetch(sn, {}), sn)
        previous.key?(sn) ? previous[sn].with(name: fresh.name, online: fresh.online) : fresh
      end

      @mutex.synchronize { @devices = list }
      @listed_at = now
    end
  end
end
