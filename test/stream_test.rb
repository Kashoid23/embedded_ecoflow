# frozen_string_literal: true

require 'test_helper'

class StreamTest < Minitest::Test
  include TestSupport
  include EcoflowDashboard

  Stream = Ecoflow::Stream

  # Starts from the cloud's snapshot (quota_all) before the broker sends anything
  class SnapshotClient < FakeClient
    def quota_all(_sn) = { 'pd.soc' => 99, 'inv.inputWatts' => 0 }
  end

  def setup
    @stream = Stream.new(client: SnapshotClient.new, sns: %w[R621], logger: Logger.new(nil))
  end

  def mqtt(type, params) = JSON.generate('typeCode' => type, 'params' => params)

  # RIVER 2 Pro on grid (live, 26.11.2026): the broker sends the inverter's input every ~3 s,
  # the cloud snapshot kept 0
  def test_messages_replace_snapshot_values_under_their_module_prefix
    @stream.seed('R621')
    @stream.receive('/open/acc/R621/quota', mqtt('invStatus', 'inputWatts' => 40, 'outputWatts' => 40), NOW)
    @stream.receive('/open/acc/R621/quota', mqtt('bmsStatus', 'inputWatts' => 0, 'outputWatts' => 2), NOW)

    assert_equal({ 'pd.soc' => 99, 'inv.inputWatts' => 40, 'bms_bmsStatus.outputWatts' => 2 },
                 @stream.quota('R621', %w[pd.soc inv.inputWatts bms_bmsStatus.outputWatts], NOW + 1))
  end

  def test_all_modules
    { 'pdStatus' => 'pd.x', 'invStatus' => 'inv.x', 'bmsStatus' => 'bms_bmsStatus.x',
      'emsStatus' => 'bms_emsStatus.x', 'mpptStatus' => 'mppt.x' }.each do |type, key|
      @stream.receive('/open/acc/R621/quota', mqtt(type, 'x' => 1), NOW)
      assert_equal({ key => 1 }, @stream.quota('R621', [key], NOW))
    end
  end

  def test_no_message_yet
    error = assert_raises(Ecoflow::Client::Error) { @stream.quota('R621', %w[pd.soc], NOW) }
    assert_match 'no live data', error.message
  end

  def test_station_gone_quiet
    @stream.receive('/open/acc/R621/quota', mqtt('pdStatus', 'soc' => 99), NOW)

    assert @stream.quota('R621', %w[pd.soc], NOW + Stream::STALE_AFTER)
    error = assert_raises(Ecoflow::Client::Error) { @stream.quota('R621', %w[pd.soc], NOW + Stream::STALE_AFTER + 1) }
    assert_match 'no live data for', error.message
  end

  # DELTA 2 Max (live, 26.11.2026): setReportCfg asks for a full report every 300 s and only changes
  # in between, so an idle station may stay silent for a whole report period
  def test_idle_station_between_full_reports_is_still_live
    @stream.receive('/open/acc/R621/quota', mqtt('pdStatus', 'soc' => 99), NOW)

    assert_equal({ 'pd.soc' => 99 }, @stream.quota('R621', %w[pd.soc], NOW + 300 + 30))
  end

  # The station's report settings (sent on subscribe) carry no typeCode and no readings, but show
  # the station is there: an idle DELTA 2 Max may send nothing else for 5 min, and its snapshot
  # values must show meanwhile (otherwise the first samples after a start come out empty)
  def test_report_settings_mean_alive_but_are_not_data
    @stream.seed('R621')
    report_cfg = JSON.generate('moduleType' => 1, 'instructCode' => 'setReportCfg',
                               'params' => { 'pdInfoFull' => 300_000 })
    @stream.receive('/open/acc/R621/quota', report_cfg, NOW)

    assert_equal({ 'pd.soc' => 99 }, @stream.quota('R621', %w[pd.soc .pdInfoFull pdInfoFull], NOW))
  end

  def test_snapshot_alone_is_not_live
    @stream.seed('R621')
    assert_raises(Ecoflow::Client::Error) { @stream.quota('R621', %w[pd.soc], NOW) }
  end

  def test_offline_status
    @stream.receive('/open/acc/R621/quota', mqtt('pdStatus', 'soc' => 99), NOW)
    @stream.receive('/open/acc/R621/status', JSON.generate('params' => { 'status' => 0 }), NOW)

    error = assert_raises(Ecoflow::Client::Error) { @stream.quota('R621', %w[pd.soc], NOW) }
    assert_match 'offline', error.message

    @stream.receive('/open/acc/R621/status', JSON.generate('params' => { 'status' => 1 }), NOW)
    @stream.receive('/open/acc/R621/quota', mqtt('pdStatus', 'soc' => 98), NOW)
    assert_equal({ 'pd.soc' => 98 }, @stream.quota('R621', %w[pd.soc], NOW))
  end

  def test_ignores_garbage
    @stream.receive('/open/acc/R621/quota', 'not json', NOW)
    @stream.receive('/open/acc/R621/quota', JSON.generate('typeCode' => 'pdStatus'), NOW)
    @stream.receive('/open/acc/OTHER/quota', mqtt('pdStatus', 'soc' => 1), NOW)

    assert_raises(Ecoflow::Client::Error) { @stream.quota('R621', %w[pd.soc], NOW) }
  end

  class FailingClient < FakeClient
    def quota_all(_sn) = raise(EcoflowDashboard::Ecoflow::Client::Error, 'API 1006: not allowed')
  end

  def test_failing_snapshot_is_skipped
    stream = Stream.new(client: FailingClient.new, sns: %w[BBB2], logger: Logger.new(nil))
    stream.seed('BBB2') # logged, not raised
    stream.receive('/open/acc/BBB2/quota', mqtt('pdStatus', 'soc' => 50), NOW)

    assert_equal({ 'pd.soc' => 50 }, stream.quota('BBB2', %w[pd.soc], NOW))
  end

  # A station shared from another account: the cloud refuses it and the broker sends nothing
  def test_refused_station_shows_why
    stream = Stream.new(client: FailingClient.new, sns: %w[BBB2], logger: Logger.new(nil))
    stream.seed('BBB2')

    error = assert_raises(Ecoflow::Client::Error) { stream.quota('BBB2', %w[pd.soc], NOW) }
    assert_equal 'API 1006: not allowed', error.message
  end

  def test_wait_for_data_returns_once_every_station_answered_or_was_refused
    stream = Stream.new(client: FailingClient.new, sns: %w[R621 BBB2], logger: Logger.new(nil))
    stream.seed('BBB2')
    stream.receive('/open/acc/R621/quota', mqtt('pdStatus', 'soc' => 50))

    started = Time.now
    stream.wait_for_data(5, step: 0.01)
    assert_operator Time.now - started, :<, 1
  end

  def test_wait_for_data_gives_up_after_timeout
    started = Time.now
    @stream.wait_for_data(0.05, step: 0.01) # R621 never heard from
    assert_operator Time.now - started, :>=, 0.05
  end
end
