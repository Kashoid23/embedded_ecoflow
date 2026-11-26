# frozen_string_literal: true

module EcoflowDashboard
  # All configuration in one immutable object, built once from ENV (see .env.example).
  Settings = Data.define(
    :access_key, :secret_key, :region,
    :device_sns, :grid_sns,
    :sample_interval, :page_refresh,
    :oblenergo, :outage_group,
    :weather_lat, :weather_lon,
    :air_raid_provider, :air_raid_token, :air_raid_region,
    :app_env, :data_dir, :host, :port, :log_level
  ) do
    def self.from_env(env = ENV)
      value = ->(name, default = nil) { env[name].to_s.strip.then { |v| v.empty? ? default : v } }
      list  = ->(name) { env[name].to_s.split(',').map(&:strip).reject(&:empty?) }
      required = ->(name) { value.call(name) || raise(Error, "Missing #{name} in .env") }
      # Whole seconds above zero: 0 would poll the API in a tight loop
      seconds = lambda do |name, default|
        v = value.call(name, default)
        n = Integer(v, 10, exception: false)
        n&.positive? ? n : raise(Error, "#{name} must be a whole number of seconds above 0, got #{v.inspect}")
      end
      air_raid = value.call('AIR_RAID_PROVIDER')
      outage_group = value.call('OUTAGE_GROUP')

      new(
        access_key: required.call('ECOFLOW_ACCESS_KEY'),
        secret_key: required.call('ECOFLOW_SECRET_KEY'),
        region: value.call('ECOFLOW_REGION', 'eu'),
        device_sns: list.call('ECOFLOW_SN'),
        grid_sns: list.call('ECOFLOW_GRID_SN'),
        sample_interval: seconds.call('ECOFLOW_SAMPLE_INTERVAL', '60'),
        page_refresh: seconds.call('ECOFLOW_INTERVAL', '60'),
        oblenergo: (required.call('OBLENERGO') if outage_group),
        outage_group: outage_group,
        weather_lat: (required.call('WEATHER_LAT') if value.call('WEATHER_LON')),
        weather_lon: (required.call('WEATHER_LON') if value.call('WEATHER_LAT')),
        air_raid_provider: air_raid,
        air_raid_token: (required.call('AIR_RAID_TOKEN') if air_raid),
        air_raid_region: (required.call('AIR_RAID_REGION') if air_raid), # region ids differ per provider
        app_env: value.call('APP_ENV', 'development'),
        data_dir: value.call('DATA_DIR', File.join(ROOT, 'data')),
        host: value.call('BIND', '127.0.0.1'),
        port: value.call('PORT', '4567').to_i,
        log_level: value.call('LOG_LEVEL', 'info')
      )
    end

    def schedule? = !outage_group.nil?

    # Weather in the header when the coordinates are set (one without the other raises)
    def weather? = !weather_lat.nil?

    def air_raid? = !air_raid_provider.nil?

    # Stations plugged into the wall (ECOFLOW_GRID_SN). Empty = every station.
    # A station charged from another station's outlet must not be listed: during an outage
    # it still sees 230 V on its input.
    def grid_station?(sn) = grid_sns.empty? || grid_sns.include?(sn)

    # APP_ENV=production (set in the Docker image)
    def production? = app_env == 'production'
  end
end
