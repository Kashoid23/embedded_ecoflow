# frozen_string_literal: true

module EcoflowDashboard
  # Air-raid state for one region, from a pluggable provider chosen in .env (AIR_RAID_PROVIDER).
  #
  # A provider is any class with
  #   new(token:, region:)   region: the provider's own region id (ids differ between providers)
  #   fetch(now) -> Status   raising AirRaid::Error on any failure
  # registered in PROVIDERS under the name used in .env.
  module AirRaid
    Error = Class.new(EcoflowDashboard::Error)

    # A status older than this is shown as unknown: the state may have changed since
    STALE_AFTER = 180

    # state: :active (whole region) / :partial (part of it) / :none, at: when it was fetched
    Status = Data.define(:state, :at) do
      def state_at(now) = now - at > STALE_AFTER ? :unknown : state
    end

    # alerts.in.ua — free token on request (api@alerts.in.ua). Region: oblast uid.
    class AlertsInUa
      URL = 'https://api.alerts.in.ua/v1/iot/active_air_raid_alerts/%s.json'

      # The API answers one letter: A — alert in the whole oblast, P — in part of it, N — none
      STATES = { 'A' => :active, 'P' => :partial, 'N' => :none }.freeze

      def initialize(token:, region:)
        @uri     = URI(format(URL, region))
        @headers = { 'Authorization' => "Bearer #{token}" }
      end

      def fetch(now = Time.now) = parse(HttpJson.get(@uri, error: Error, headers: @headers), now)

      def parse(letter, now)
        Status.new(state: STATES.fetch(letter) { raise Error, "alerts.in.ua: unexpected answer #{letter.inspect}" },
                   at: now)
      end
    end

    # ukrainealarm.com — API key on request. Region: regionId of a district (район) or community
    # (громада): since Nov 2025 oblast-level ids no longer report alerts. Only "AIR" alerts count;
    # the API also lists artillery, urban fights etc. It has no "part of the region" state.
    class UkraineAlarm
      URL = 'https://api.ukrainealarm.com/api/v3/alerts/%s'

      def initialize(token:, region:)
        @uri     = URI(format(URL, region))
        @headers = { 'Authorization' => token, 'Accept' => 'application/json' }
      end

      def fetch(now = Time.now) = parse(HttpJson.get(@uri, error: Error, headers: @headers), now)

      # [{ "regionId" => "…", "activeAlerts" => [{ "type" => "AIR", … }] }] — an empty list when quiet
      def parse(regions, now)
        raise Error, "ukrainealarm.com: unexpected answer #{regions.class}" unless regions.is_a?(Array)

        air = regions.any? { |r| r.fetch('activeAlerts', []).any? { |a| a['type'] == 'AIR' } }
        Status.new(state: air ? :active : :none, at: now)
      end
    end

    PROVIDERS = { 'alerts_in_ua' => AlertsInUa, 'ukrainealarm' => UkraineAlarm }.freeze

    def self.source(provider:, token:, region:)
      klass = PROVIDERS.fetch(provider) do
        raise Error, "Unknown AIR_RAID_PROVIDER=#{provider} (known: #{PROVIDERS.keys.join(', ')})"
      end
      klass.new(token: token, region: region)
    end
  end
end
