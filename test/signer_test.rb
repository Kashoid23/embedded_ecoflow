# frozen_string_literal: true

require 'test_helper'

class SignerTest < Minitest::Test
  def setup
    @signer = EcoflowDashboard::Ecoflow::Signer.new('AK', 'SK')
  end

  def test_string_without_params
    assert_equal 'accessKey=AK&nonce=123456&timestamp=1700000000000',
                 @signer.string_to_sign({}, 123_456, 1_700_000_000_000)
  end

  def test_nested_params_are_flattened_and_sorted
    params = { sn: 'X1', params: { quotas: %w[pd.soc pd.wattsOutSum] } }

    assert_equal 'params.quotas[0]=pd.soc&params.quotas[1]=pd.wattsOutSum&sn=X1&accessKey=AK&nonce=1&timestamp=2',
                 @signer.string_to_sign(params, 1, 2)
  end

  def test_headers_contain_hmac_signature
    headers = @signer.headers({ sn: 'X1' }, nonce: 1, timestamp: 2)
    expected = OpenSSL::HMAC.hexdigest('SHA256', 'SK', 'sn=X1&accessKey=AK&nonce=1&timestamp=2')

    assert_equal({ 'accessKey' => 'AK', 'nonce' => '1', 'timestamp' => '2', 'sign' => expected }, headers)
  end
end
