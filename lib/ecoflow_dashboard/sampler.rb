# frozen_string_literal: true

module EcoflowDashboard
  # Polls every station once per call to #tick: keeps the latest values in memory
  # (for the dashboard cards) and appends a sample per station to the SampleStore.
  class Sampler
    # grid: true/false whether this station runs from the grid, nil when it can't be told
    Device = Data.define(:sn, :name, :online, :values, :grid, :error) do
      def self.from_api(hash, sn)
        new(sn: sn, name: hash['productName'] || hash['deviceName'] || sn,
            online: hash['online'].to_i == 1, values: {}, grid: nil, error: nil)
      end
    end

    # Always requested: the stats and the station rows need them
    STAT_KEYS = %w[pd.soc pd.wattsInSum pd.wattsOutSum].freeze

    # Remaining charge (mAh) and pack voltage (mV) from the battery management system, for the
    # backup estimate. Not every model reports them (RIVER 2 Pro doesn't); missing keys are just absent.
    BATTERY_KEYS = %w[bms_bmsStatus.remainCap bms_bmsStatus.vol].freeze

    # Requested from every station
    POLL_KEYS = (STAT_KEYS + BATTERY_KEYS + GridDetector::KEYS + [BatteryTrend::KEY]).uniq.freeze

    DEVICE_LIST_TTL = 3600

    def initialize(client:, store:, settings:)
      @client   = client
      @store    = store
      @settings = settings
      @mutex    = Mutex.new
      @devices  = []
      @trend    = BatteryTrend.new
    end

    def devices = @mutex.synchronize { @devices.dup }

    def tick(now = Time.now)
      refresh_device_list(now)

      # Stations are independent: poll them in parallel so a tick costs one round trip, not N
      updated = devices.map { |device| Thread.new { poll(device, now) } }.map(&:value)
      @mutex.synchronize { @devices = updated.map(&:first) }
      @store.append(now, updated.filter_map(&:last))
    end

    private

    # Returns [device_with_latest_values, sample_row_or_nil]
    # Never raises: a failure of one station must not lose the other stations' samples
    def poll(device, now)
      data = @client.quota(device.sn, POLL_KEYS)
      raise Ecoflow::Client::Error, "no quota data (#{data.class})" unless data.is_a?(Hash)

      grid_station = @settings.grid_station?(device.sn)
      grid = GridDetector.grid?(data, @trend.falling?(device.sn, data, now))

      # Only grid stations decide whether the house has power
      row = { sn: device.sn, soc: data['pd.soc'], in: GridDetector.watts(data),
              out: data['pd.wattsOutSum'], grid: (grid if grid_station) }
      row.merge!(GridDetector.readings(data)) if grid_station
      [device.with(values: data, grid: grid, error: nil), row]
    rescue StandardError => e
      message = e.is_a?(Ecoflow::Client::Error) ? e.message : "#{e.class}: #{e.message}"
      [device.with(error: message), nil]
    end

    def refresh_device_list(now)
      return if @listed_at && now - @listed_at < DEVICE_LIST_TTL

      from_api = @client.devices.to_h { |d| [d['sn'], d] }
      sns      = @settings.device_sns.empty? ? from_api.keys : @settings.device_sns
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
