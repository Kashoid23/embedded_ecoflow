# frozen_string_literal: true

require 'test_helper'

class WeatherTest < Minitest::Test
  include EcoflowDashboard

  # Shape of an Open-Meteo /v1/forecast response with `current=...`
  RESPONSE = {
    'latitude' => 50.0, 'longitude' => 30.0,
    'current' => { 'time' => '2026-11-26T12:00', 'temperature_2m' => 3.4, 'weather_code' => 2, 'is_day' => 1 }
  }.freeze

  def source = Weather::OpenMeteoSource.new(lat: '50.0', lon: '30.0')

  def test_parses_current_weather
    report = source.parse(RESPONSE)

    assert_equal Weather::Report.new(temp: 3.4, code: 2, day: true), report
    assert_equal :partly, report.kind
  end

  def test_response_without_current_weather
    assert_raises(Weather::Error) { source.parse({}) }
    assert_raises(Weather::Error) { source.parse({ 'current' => nil }) }
    assert_raises(Weather::Error) { source.parse({ 'current' => { 'temperature_2m' => nil, 'weather_code' => 2 } }) }
  end

  def test_unknown_code_falls_back_to_cloud
    assert_equal :cloudy, Weather::Report.new(temp: 0, code: 42, day: true).kind
  end

  class Icons
    include EcoflowDashboard::Web::WeatherIcons
  end

  def test_icon_for_every_kind_and_day_and_night
    codes = [0, 2, 3, 45, 61, 71, 95]
    [true, false].product(codes).each do |day, code|
      svg = Icons.new.weather_icon(Weather::Report.new(temp: 0, code: code, day: day))

      assert_match(%r{\A<svg .*</svg>\z}m, svg)
    end
    assert_match 'w-moon', Icons.new.weather_icon(Weather::Report.new(temp: 0, code: 0, day: false))
  end

  def test_temperature_uses_a_real_minus
    icons = Icons.new

    assert_equal ['3°', '−3°', '0°'], [icons.temperature(3.4), icons.temperature(-2.6), icons.temperature(-0.2)]
  end
end
