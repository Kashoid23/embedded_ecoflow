# frozen_string_literal: true

require 'test_helper'

class SettingsTest < Minitest::Test
  include TestSupport

  def test_defaults
    s = settings

    assert_equal 'eu', s.region
    assert_empty s.device_sns
    assert_equal 60, s.sample_interval
    refute_predicate s, :schedule?
  end

  def test_lists
    s = settings('ECOFLOW_SN' => 'A1, B2', 'OUTAGE_GROUP' => '23.1')

    assert_equal %w[A1 B2], s.device_sns
    assert_predicate s, :schedule?
  end

  def test_grid_stations
    assert settings.grid_station?('ANY')

    s = settings('ECOFLOW_GRID_SN' => 'A1')
    assert s.grid_station?('A1')
    refute s.grid_station?('B2')
  end

  def test_weather_needs_both_coordinates
    refute_predicate settings, :weather?
    assert_predicate settings('WEATHER_LAT' => '50.0', 'WEATHER_LON' => '30.0'), :weather?

    error = assert_raises(EcoflowDashboard::Error) { settings('WEATHER_LAT' => '50.0') }
    assert_match 'WEATHER_LON', error.message
  end

  def test_outage_group_requires_oblenergo
    error = assert_raises(EcoflowDashboard::Error) do
      settings('OUTAGE_GROUP' => '1.1', 'OBLENERGO' => '')
    end
    assert_match 'OBLENERGO', error.message
  end

  def test_missing_key_raises
    error = assert_raises(EcoflowDashboard::Error) do
      EcoflowDashboard::Settings.from_env('ECOFLOW_SECRET_KEY' => 'x')
    end
    assert_match 'ECOFLOW_ACCESS_KEY', error.message
  end

  def test_intervals_must_be_positive_seconds
    %w[0 1m -5].each do |bad|
      error = assert_raises(EcoflowDashboard::Error) { settings('ECOFLOW_SAMPLE_INTERVAL' => bad) }
      assert_match 'ECOFLOW_SAMPLE_INTERVAL', error.message
    end
    assert_raises(EcoflowDashboard::Error) { settings('ECOFLOW_INTERVAL' => 'abc') }
    assert_equal 30, settings('ECOFLOW_SAMPLE_INTERVAL' => '30').sample_interval
  end
end
