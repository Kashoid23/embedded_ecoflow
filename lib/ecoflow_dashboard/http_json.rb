# frozen_string_literal: true

module EcoflowDashboard
  # Send a request and parse the JSON answer. Network, HTTP and parse failures are raised as `error`.
  module HttpJson
    module_function

    TIMEOUT = 10 # seconds, for connecting and for each read

    def get(uri, error:, headers: {})
      request(Net::HTTP::Get.new(uri, headers), error: error)
    end

    def request(req, error:)
      uri      = req.uri
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                     open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(req)
      end
      raise error, "#{uri.host}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue *NETWORK_ERRORS, JSON::ParserError => e
      raise error, "#{uri.host}: #{e.class}: #{e.message}"
    end
  end
end
