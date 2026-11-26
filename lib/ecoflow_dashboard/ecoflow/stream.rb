# frozen_string_literal: true

module EcoflowDashboard
  module Ecoflow
    # Live station values from EcoFlow's MQTT broker (IoT Open Platform).
    #
    # The HTTP quota endpoint serves the cloud's cached copy, which lags and can be wrong: on
    # 26.11.2026 it gave RIVER 2 Pro's inv.inputWatts as 0 while the station itself sent 40 W every
    # 3 s over MQTT. So the stations' own messages are the source; the HTTP snapshot (quota/all)
    # only fills keys a station hasn't sent yet (DELTA 2 Max sends a module only when it changes).
    #
    # Each message carries one module: { "typeCode": "invStatus", "params": { "inputWatts": 40 } }.
    # Its keys are stored under the HTTP names ("inv.inputWatts"), so the rest of the app reads both alike.
    #
    # Topics: /open/{account}/{sn}/quota (values) and /open/{account}/{sn}/status (online 1 / offline 0).
    class Stream
      MODULES = { 'pdStatus' => 'pd', 'invStatus' => 'inv', 'bmsStatus' => 'bms_bmsStatus',
                  'emsStatus' => 'bms_emsStatus', 'mpptStatus' => 'mppt' }.freeze

      # Without a message from a station for this long its values are no longer trusted.
      # DELTA 2 Max sends a full report every 5 min (setReportCfg: pdInfoFull 300000 ms) and only
      # changes in between, so an idle station can be silent for a whole period: allow two of them.
      STALE_AFTER = 11 * 60
      RETRY_AFTER = 10 # s, before reconnecting after a broken connection

      # error: why the cloud refused the station's snapshot (e.g. API 1006 for a station shared from
      # another account); such a station sends nothing over MQTT either
      Station = Struct.new(:quotas, :heard_at, :online, :error)

      # sns: the stations' serial numbers, or a callable returning them (asked on every connect)
      def initialize(client:, sns:, logger:)
        @client  = client
        @sns     = sns
        @logger  = logger
        @mutex   = Mutex.new
        @station = {}
        watch(sns) unless sns.respond_to?(:call)
      end

      # Connects in a background thread and keeps reconnecting
      def start = Periodic.start('mqtt', RETRY_AFTER, logger: @logger) { listen }

      # Blocks until every station has sent something or been refused, at most `timeout` seconds,
      # so the first sample after a start doesn't find every station still silent
      def wait_for_data(timeout, step: 0.5)
        deadline = Time.now + timeout
        sleep step until ready? || Time.now >= deadline
      end

      # The latest values of the given keys, {} when the station hasn't sent anything since the start;
      # raises Client::Error when the station was refused, is offline or hasn't sent anything for STALE_AFTER
      def quota(sn, keys, now = Time.now)
        @mutex.synchronize do
          station = @station[sn]
          unless station&.heard_at
            raise Client::Error, station.error if station&.error

            return {}
          end
          raise Client::Error, 'offline' unless station.online

          quiet = now - station.heard_at
          raise Client::Error, "no live data for #{(quiet / 60).round} min" if quiet > STALE_AFTER

          station.quotas.slice(*keys)
        end
      end

      # One broker message
      def receive(topic, payload, now = Time.now)
        sn, kind = topic.split('/').last(2)
        data = JSON.parse(payload)
        return unless data.is_a?(Hash) && data['params'].is_a?(Hash)

        @mutex.synchronize do
          station = @station[sn] or return
          next status(station, data['params']) if kind == 'status'

          # Any quota message means the station is there. Values always come with a typeCode:
          # without one it's the report settings (setReportCfg, sent on subscribe), no readings
          station.heard_at = now
          update(station, data) if data['typeCode']
        end
      rescue JSON::ParserError
        nil
      end

      # Fills a station's values from the cloud snapshot, under what it already sent live.
      # Doesn't count as hearing from it.
      def seed(sn)
        snapshot = @client.quota_all(sn)
        return unless snapshot.is_a?(Hash)

        @mutex.synchronize do
          station = @station[sn] or return
          station.quotas = snapshot.merge(station.quotas)
          station.error  = nil
        end
      rescue Client::Error => e
        @logger.warn("mqtt: snapshot of #{sn}: #{e.message}")
        @mutex.synchronize { @station[sn]&.error = e.message }
      end

      private

      def ready?
        @mutex.synchronize { !@station.empty? && @station.each_value.all? { |s| s.heard_at || s.error } }
      end

      def watch(sns)
        @mutex.synchronize { sns.each { |sn| @station[sn] ||= Station.new({}, nil, true, nil) } }
        sns
      end

      def listen
        sns  = watch(@sns.respond_to?(:call) ? @sns.call : @sns)
        cert = @client.certification
        broker(cert).connect do |connection|
          connection.subscribe(*topics(cert['certificateAccount'], sns))
          # Only the first time: after a reconnect the station's values are already in memory
          sns.each { |sn| seed(sn) if @mutex.synchronize { @station[sn].quotas.empty? } }
          @logger.info("mqtt: connected, #{sns.size} stations")
          connection.get { |topic, payload| receive(topic, payload) }
        end
      end

      def broker(cert)
        MQTT::Client.new(host: cert['url'], port: cert['port'].to_i, ssl: true,
                         username: cert['certificateAccount'], password: cert['certificatePassword'],
                         client_id: "dashboard_#{SecureRandom.hex(8)}")
      end

      def topics(account, sns) = sns.flat_map { |sn| ["/open/#{account}/#{sn}/quota", "/open/#{account}/#{sn}/status"] }

      # { "status": 1 } online, 0 offline
      def status(station, params)
        station.online = params['status'].to_i == 1 if params.key?('status')
      end

      # { "typeCode": "invStatus", "params": { "inputWatts": 40 } } -> "inv.inputWatts" => 40
      def update(station, data)
        prefix = MODULES.fetch(data['typeCode'].to_s, data['typeCode'])
        data['params'].each { |key, value| station.quotas["#{prefix}.#{key}"] = value }
      end
    end
  end
end
