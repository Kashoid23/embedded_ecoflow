# frozen_string_literal: true

require 'date'
require 'json'
require 'logger'
require 'net/http'
require 'openssl'

# EcoFlow stations + power outage schedule dashboard.
module EcoflowDashboard
  Error = Class.new(StandardError)

  ROOT = File.expand_path('..', __dir__)

  # Failures of an outgoing HTTPS request, rescued by every HTTP client in the app
  # (Timeout::Error covers Net::OpenTimeout / ReadTimeout / WriteTimeout, IOError covers EOFError)
  NETWORK_ERRORS = [SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError,
                    Net::ProtocolError, Net::HTTPBadResponse].freeze

  # The latest value of a background feed (weather, air raid), replaced by its job.
  # A single reference swap, so no lock is needed.
  Latest = Struct.new(:value)
end

require_relative 'ecoflow_dashboard/settings'
require_relative 'ecoflow_dashboard/periodic'
require_relative 'ecoflow_dashboard/http_json'
require_relative 'ecoflow_dashboard/ecoflow/signer'
require_relative 'ecoflow_dashboard/ecoflow/client'
require_relative 'ecoflow_dashboard/outages/oblenergo_source'
require_relative 'ecoflow_dashboard/outages/schedule'
require_relative 'ecoflow_dashboard/weather'
require_relative 'ecoflow_dashboard/air_raid'
require_relative 'ecoflow_dashboard/sample_store'
require_relative 'ecoflow_dashboard/grid_detector'
require_relative 'ecoflow_dashboard/battery_trend'
require_relative 'ecoflow_dashboard/sampler'
require_relative 'ecoflow_dashboard/day_stats'
require_relative 'ecoflow_dashboard/history'
require_relative 'ecoflow_dashboard/web/helpers'
require_relative 'ecoflow_dashboard/web/weather_icons'
require_relative 'ecoflow_dashboard/web/view'
require_relative 'ecoflow_dashboard/web/dashboard'
require_relative 'ecoflow_dashboard/web/app'
