# frozen_string_literal: true

module EcoflowDashboard
  module Ecoflow
    # Minimal client for the EcoFlow Developer API (IoT Open Platform).
    class Client
      Error = Class.new(EcoflowDashboard::Error)

      HOSTS = {
        'eu' => 'https://api-e.ecoflow.com',
        'us' => 'https://api-a.ecoflow.com',
        'global' => 'https://api.ecoflow.com'
      }.freeze

      def initialize(access_key:, secret_key:, region: 'eu', logger: Logger.new(nil))
        @base   = HOSTS.fetch(region) { raise ArgumentError, "unknown region: #{region}" }
        @signer = Signer.new(access_key, secret_key)
        @logger = logger
      end

      # [{ "sn" => "...", "productName" => "...", "online" => 1 }, ...]
      def devices = get('/iot-open/sign/device/list')

      # Every quota (property) of a device: { "pd.soc" => 87, ... }
      def quota_all(sn) = get('/iot-open/sign/device/quota/all', sn: sn)

      # MQTT broker login: { "certificateAccount", "certificatePassword", "url", "port", "protocol" }
      def certification = get('/iot-open/sign/certification')

      private

      def get(path, params = {})
        uri = URI(@base + path)
        uri.query = URI.encode_www_form(params) unless params.empty?
        request = Net::HTTP::Get.new(uri)
        @signer.headers(params).each { |name, value| request[name] = value }
        @logger.debug { "#{request.method} #{request.uri}" }

        json = HttpJson.request(request, error: Error)
        raise Error, "API #{json['code']}: #{json['message']}" unless json['code'].to_s == '0'

        json['data']
      end
    end
  end
end
