# frozen_string_literal: true

require 'test_helper'

class SamplerTest < Minitest::Test
  include TestSupport
  include EcoflowDashboard

  # BBB2 fails with something other than Client::Error, or answers without data
  class BrokenClient < FakeClient
    attr_accessor :failure

    def quota(sn, keys)
      return super unless sn == 'BBB2'
      raise failure if failure

      nil
    end
  end

  def setup
    @tmp    = Dir.mktmpdir
    @client = BrokenClient.new
    @store  = SampleStore.new(File.join(@tmp, 'samples'))
  end

  def tick
    sampler = Sampler.new(client: @client, source: @client, store: @store, settings: settings)
    sampler.tick(NOW)
    sampler
  end

  def assert_other_station_still_sampled(sampler, error)
    assert_equal(['AAA1'], @store.read(NOW.to_date).map { |r| r['sn'] })
    broken = sampler.devices.find { |d| d.sn == 'BBB2' }
    assert_match error, broken.error
  end

  def test_network_error_of_one_station
    @client.failure = EOFError.new('end of file reached')
    assert_other_station_still_sampled(tick, 'EOFError')
  end

  # Nothing from the station since the start: no error, no values (shown as "—"), no sample
  def test_station_without_live_data_yet
    @client.missing = Sampler::POLL_KEYS
    waiting = tick.devices.find { |d| d.sn == 'AAA1' }

    assert_empty @store.read(NOW.to_date)
    assert_nil waiting.error
    assert_empty waiting.values
  end

  def test_station_without_quota_data
    assert_other_station_still_sampled(tick, 'no quota data')
  end
end
