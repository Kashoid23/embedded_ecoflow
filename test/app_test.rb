# frozen_string_literal: true

require 'test_helper'

class AppTest < Minitest::Test
  include TestSupport
  include EcoflowDashboard

  def setup
    @tmp      = Dir.mktmpdir
    @settings = settings('OUTAGE_GROUP' => '1.1')
    @client   = FakeClient.new
    @store    = SampleStore.new(File.join(@tmp, 'samples'))
    @schedule = Outages::Schedule.new
    @sampler  = Sampler.new(client: @client, source: @client, store: @store, settings: @settings)

    # 10:00–12:00, power lost at 11:00
    (600...720).each do |minute|
      @client.grid = minute < 660
      @sampler.tick(Time.new(2026, 11, 26) + minute * 60)
    end

    @weather = Latest.new
    @app = Web::App.new(settings: @settings, client: @client, sampler: @sampler, store: @store,
                        schedule: @schedule, weather: @weather, views: File.join(ROOT, 'views'), clock: -> { NOW })
  end

  def production_app
    Web::App.new(settings: settings('OUTAGE_GROUP' => '1.1', 'APP_ENV' => 'production'),
                 client: @client, sampler: @sampler, store: @store,
                 schedule: @schedule, weather: @weather, clock: -> { NOW })
  end

  def test_production_hides_stations_table
    body = production_app.call('/')[2]

    refute_match 'Time left', body       # table header
    refute_match '/device/AAA1', body    # links to the raw-values pages are in the table only
    assert_match 'DELTA 2 Max', body     # the station cards stay
    assert_match 'Time left', @app.call('/')[2] # development still shows it
  end

  def test_production_has_no_raw_data_pages
    app = production_app
    def @client.quota_all(_sn) = raise('must not reach the EcoFlow API')

    status, = app.call('/device/AAA1')
    assert_equal 404, status

    status, = app.call('/api/status.json') # the same raw values and serial numbers
    assert_equal 404, status
  end

  def test_dashboard
    status, headers, body = @app.call('/')

    assert_equal 200, status
    assert_match 'text/html', headers['Content-Type']
    assert_match(/class="card banner bad">/, body) # status banner
    assert_match '<strong>No power</strong>', body
    assert_match 'since 11:00', body
    refute_match 'unplanned', body
    assert_match %r{Without power today</div>\s*<div class="value bad">1h 00m</div>}, body
    assert_match 'now 100 W · backup ~16 h', body   # 30 Ah × 54 V = 1620 Wh / 100 W
    assert_match 'API 1006: not allowed', body      # station that can't be read
    # still listed
    assert_match %r{<span class="name">RIVER 3</span>\s*<span class="chip caps muted">unavailable</span>}, body
    assert_match 'DELTA 2 Max', body
    refute_match 'row-label', body # timeline rows have no labels
    refute_match 'Total output', body
  end

  def test_only_grid_stations_decide
    # BBB2 can't be read anyway; AAA1 is the only grid station, so the result is the same,
    # but a non-grid station must get grid: nil in the samples
    s = settings('ECOFLOW_GRID_SN' => 'ZZZ9')
    store = SampleStore.new(File.join(@tmp, 'other'))
    Sampler.new(client: @client, source: @client, store: store, settings: s).tick(NOW)

    assert_nil store.read(NOW.to_date).first['grid']
  end

  # Nothing flows in or out of the grid station: stored as idle, not as a decision
  def test_idle_grid_station_sample
    store = SampleStore.new(File.join(@tmp, 'idle'))
    @client.out = 0
    Sampler.new(client: @client, source: @client, store: store, settings: @settings).tick(NOW)

    assert_equal 'idle', store.read(NOW.to_date).first['grid']
  end

  # The battery readings behind the grid decision are kept in each sample, to check it against a real outage
  def test_samples_keep_grid_readings
    store = SampleStore.new(File.join(@tmp, 'readings'))
    sampler = Sampler.new(client: @client, source: @client, store: store, settings: @settings)
    @client.grid = false
    sampler.tick(NOW)
    row = store.read(NOW.to_date).first

    assert_equal({ 'grid' => false, 'in' => 0.0, 'bat' => 100 }, row.slice('grid', 'in', 'bat'))

    @client.missing = %w[bms_bmsStatus.outputWatts] # a station that doesn't report a reading gets no such field
    sampler.tick(NOW + 60)
    refute_includes store.read(NOW.to_date).last.keys, 'bat'
  end

  def test_one_page_for_both_screens
    _, _, body = @app.call('/')

    assert_match '@media (max-width: 520px) and (max-height: 520px)', body # compact 480×480 layout
  end

  def test_weather_in_the_header
    refute_match 'class="weather"', @app.call('/')[2] # nothing until the first fetch

    @weather.value = Weather::Report.new(temp: -2.6, code: 71, day: true)
    body = @app.call('/')[2]

    assert_match '<strong>−3°</strong>', body
    refute_match 'title=', body # no tooltips anywhere
    assert_match 'class="w-snow"', body
    refute_match 'Power control room</a>', body # the title is gone
  end

  def test_air_raid_siren
    refute_match '<svg class="siren', @app.call('/')[2] # off without AIR_RAID_PROVIDER

    air_raid = Latest.new
    env = { 'AIR_RAID_PROVIDER' => 'alerts_in_ua', 'AIR_RAID_TOKEN' => 't', 'AIR_RAID_REGION' => '7' }
    app = Web::App.new(settings: settings(env), client: @client, sampler: @sampler,
                       store: @store, schedule: @schedule, air_raid: air_raid, clock: -> { NOW })

    assert_match 'class="siren unknown"', app.call('/')[2] # nothing fetched yet

    air_raid.value = AirRaid::Status.new(state: :partial, at: NOW - 30)

    assert_match 'class="siren partial"', app.call('/')[2]
  end

  def test_device_page
    status, _, body = @app.call('/device/AAA1')

    assert_equal 200, status
    assert_match 'inv.acInVol', body
  end

  def test_status_json
    _, _, body = @app.call('/api/status.json')
    json = JSON.parse(body)

    assert_equal 60, json.dig('today', 'off_minutes')
    assert_equal 60, json.dig('month', 'off_minutes')
    assert_equal 2, json['devices'].size
  end

  def test_not_found
    assert_equal 404, @app.call('/nope').first
  end

  def test_html_is_escaped
    status, _, body = @app.call('/<b>x</b>')

    assert_equal 404, status
    assert_match '&lt;b&gt;x&lt;/b&gt;', body
    refute_match '<b>x</b>', body
  end

  def test_health_check
    assert_equal [200, 'ok'], @app.call('/healthz').values_at(0, 2)
  end

  def test_icons_and_manifest
    status, headers, body = @app.call('/apple-touch-icon.png')
    assert_equal 200, status
    assert_equal 'image/png', headers['Content-Type']
    assert body.start_with?("\x89PNG".b)

    assert_equal 200, @app.call('/icon-512.png').first

    status, headers, body = @app.call('/manifest.webmanifest')
    assert_equal 200, status
    assert_equal 'application/manifest+json', headers['Content-Type']
    assert_equal '/icon-512.png', JSON.parse(body)['icons'].first['src']
  end
end
