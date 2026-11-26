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

      # Only the given quota keys
      def quota(sn, keys) = post('/iot-open/sign/device/quota', sn: sn, params: { quotas: keys })

      private

      def get(path, params = {})
        uri = URI(@base + path)
        uri.query = URI.encode_www_form(params) unless params.empty?
        perform(Net::HTTP::Get.new(uri), params)
      end

      def post(path, body)
        request = Net::HTTP::Post.new(URI(@base + path))
        # The server reads signed params from the JSON body only when this header is set,
        # so it must NOT be sent with GET requests (that gives "8521 signature is wrong").
        request['Content-Type'] = 'application/json;charset=UTF-8'
        request.body = JSON.generate(body)
        perform(request, body)
      end

      def perform(request, params)
        @signer.headers(params).each { |name, value| request[name] = value }
        @logger.debug { "#{request.method} #{request.uri}" }

        json = HttpJson.request(request, error: Error)
        raise Error, "API #{json['code']}: #{json['message']}" unless json['code'].to_s == '0'

        json['data']
      end
    end
  end
end
