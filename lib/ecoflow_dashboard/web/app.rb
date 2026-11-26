# frozen_string_literal: true

module EcoflowDashboard
  module Web
    # Routes a request path to a page. Returns [status, headers, body],
    # so it doesn't depend on the web server in use.
    class App
      HTML      = { 'Content-Type' => 'text/html; charset=utf-8' }.freeze
      JSON_TYPE = { 'Content-Type' => 'application/json' }.freeze
      TEXT      = { 'Content-Type' => 'text/plain' }.freeze

      # Home screen icons and the web app manifest
      PUBLIC = {
        '/apple-touch-icon.png' => 'image/png',
        '/icon-512.png' => 'image/png',
        '/manifest.webmanifest' => 'application/manifest+json'
      }.freeze

      def initialize(settings:, client:, sampler:, store:, schedule:,
                     weather: Latest.new, air_raid: Latest.new,
                     views: File.join(ROOT, 'views'), public: File.join(ROOT, 'public'), clock: -> { Time.now })
        @settings = settings
        @client   = client
        @sampler  = sampler
        @history  = History.new(store: store, interval: settings.sample_interval)
        @schedule = schedule
        @weather  = weather
        @air_raid = air_raid
        @view     = View.new(views)
        @clock    = clock
        # A few small files: read once, served from memory
        @public   = PUBLIC.to_h do |path, type|
          headers = { 'Content-Type' => type, 'Cache-Control' => 'public, max-age=86400' }.freeze
          [path, [200, headers, File.binread(File.join(public, path)).freeze].freeze]
        end
      end

      def call(path)
        return [200, TEXT, 'ok'] if path == '/healthz' # for the hosting health check
        return @public[path] if @public.key?(path)

        case path
        when '/'                        then html(:index, page: dashboard, refresh: @settings.page_refresh)
        when %r{\A/device/(?<sn>\w+)\z} then dev_only(path) { device(Regexp.last_match[:sn]) }
        when '/api/status.json'         then dev_only(path) { [200, JSON_TYPE, JSON.pretty_generate(status)] }
        else not_found(path)
        end
      rescue Ecoflow::Client::Error => e
        html(:error, status: 502, message: e.message)
      end

      private

      def dashboard
        Dashboard.new(now: @clock.call, devices: @sampler.devices, history: @history,
                      schedule: @schedule, settings: @settings, weather: @weather.value,
                      air_raid: @air_raid.value)
      end

      def not_found(path) = html(:not_found, status: 404, path: path)

      # Raw station values and serial numbers: development only,
      # production answers as if there were no such page
      def dev_only(path) = @settings.production? ? not_found(path) : yield

      def device(sn)
        device = @sampler.devices.find { |d| d.sn == sn }
        html(:device, device: device, sn: sn, quotas: @client.quota_all(sn).sort.to_h)
      end

      def status
        page = dashboard
        {
          devices: page.devices.map(&:to_h),
          today: { consumed_wh: page.stats.consumed_wh.round, off_minutes: page.stats.off_minutes.round },
          month: { consumed_wh: page.month.consumed_wh.round, off_minutes: page.month.off_minutes.round },
          planned_outages: @schedule.outages(page.today)
        }
      end

      def html(view, status: 200, **locals)
        [status, HTML, @view.page(view, **locals)]
      end
    end
  end
end
