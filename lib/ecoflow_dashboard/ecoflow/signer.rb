# frozen_string_literal: true

require 'openssl'
require 'securerandom'

module EcoflowDashboard
  module Ecoflow
    # Builds the auth headers for the EcoFlow Developer API.
    #
    # sign = HMAC-SHA256(secretKey, "<sorted request params>&accessKey=..&nonce=..&timestamp=..")
    # Nested params are flattened: {params: {quotas: ["a"]}} -> "params.quotas[0]=a".
    class Signer
      def initialize(access_key, secret_key)
        @access_key = access_key
        @secret_key = secret_key
      end

      def headers(params = {}, nonce: random_nonce, timestamp: current_timestamp)
        {
          'accessKey' => @access_key,
          'nonce' => nonce.to_s,
          'timestamp' => timestamp.to_s,
          'sign' => OpenSSL::HMAC.hexdigest('SHA256', @secret_key, string_to_sign(params, nonce, timestamp))
        }
      end

      def string_to_sign(params, nonce, timestamp)
        pairs = flatten(params).sort_by(&:first).map { |key, value| "#{key}=#{value}" }
        pairs.push("accessKey=#{@access_key}", "nonce=#{nonce}", "timestamp=#{timestamp}").join('&')
      end

      private

      def flatten(value, prefix = nil)
        case value
        when Hash  then value.flat_map { |k, v| flatten(v, prefix ? "#{prefix}.#{k}" : k.to_s) }
        when Array then value.each_with_index.flat_map { |v, i| flatten(v, "#{prefix}[#{i}]") }
        else [[prefix, value]]
        end
      end

      def random_nonce = SecureRandom.random_number(100_000..999_999)

      def current_timestamp = (Time.now.to_f * 1000).to_i
    end
  end
end
