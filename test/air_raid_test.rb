# frozen_string_literal: true

require 'test_helper'

class AirRaidTest < Minitest::Test
  include TestSupport
  include EcoflowDashboard

  def alerts_in_ua = AirRaid::AlertsInUa.new(token: 't', region: '7')

  def ukrainealarm = AirRaid::UkraineAlarm.new(token: 't', region: '1001')

  def test_alerts_in_ua_letters_map_to_states
    assert_equal(%i[active partial none], %w[A P N].map { |letter| alerts_in_ua.parse(letter, NOW).state })
  end

  def test_alerts_in_ua_unexpected_answer
    assert_raises(AirRaid::Error) { alerts_in_ua.parse('X', NOW) }
  end

  def test_ukrainealarm_counts_only_air_alerts
    region = ->(*types) { [{ 'regionId' => '1001', 'activeAlerts' => types.map { |t| { 'type' => t } } }] }

    assert_equal :active, ukrainealarm.parse(region.call('ARTILLERY', 'AIR'), NOW).state
    assert_equal :none,   ukrainealarm.parse(region.call('ARTILLERY'), NOW).state
    assert_equal :none,   ukrainealarm.parse(region.call, NOW).state
    assert_equal :none,   ukrainealarm.parse([], NOW).state
  end

  def test_ukrainealarm_unexpected_answer
    assert_raises(AirRaid::Error) { ukrainealarm.parse({ 'error' => 'x' }, NOW) }
  end

  def test_provider_from_settings
    assert_instance_of AirRaid::UkraineAlarm, AirRaid.source(provider: 'ukrainealarm', token: 't', region: '1')
    assert_raises(AirRaid::Error) { AirRaid.source(provider: 'nope', token: 't', region: '1') }
  end

  def test_provider_needs_token_and_region
    assert_raises(Error) { settings('AIR_RAID_PROVIDER' => 'alerts_in_ua', 'AIR_RAID_REGION' => '7') }
    assert_raises(Error) { settings('AIR_RAID_PROVIDER' => 'alerts_in_ua', 'AIR_RAID_TOKEN' => 't') }
    refute_predicate settings, :air_raid?
  end

  def test_old_status_is_unknown
    status = AirRaid::Status.new(state: :active, at: NOW)

    assert_equal :active, status.state_at(NOW + 60)
    assert_equal :unknown, status.state_at(NOW + AirRaid::STALE_AFTER + 1)
  end
end
