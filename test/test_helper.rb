# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'ecoflow_dashboard'

module TestSupport
  ENV_BASE = { 'ECOFLOW_ACCESS_KEY' => 'ak', 'ECOFLOW_SECRET_KEY' => 'sk', 'OBLENERGO' => 'Exampleoblenergo' }.freeze

  NOW = Time.new(2026, 11, 26, 12, 0)

  # Tests that need a data directory create it as @tmp in setup; it is removed here
  def teardown = (FileUtils.rm_rf(@tmp) if @tmp)

  def settings(env = {})
    EcoflowDashboard::Settings.from_env(ENV_BASE.merge('DATA_DIR' => @tmp || Dir.tmpdir).merge(env))
  end

  # Stands in for Ecoflow::Client
  class FakeClient
    attr_accessor :grid, :out, :soc, :missing # soc: BatteryTrend charge, nil = not reported; missing: quota keys this station doesn't report

    def initialize
      @grid    = true
      @out     = 100
      @missing = []
    end

    def devices
      [{ 'sn' => 'AAA1', 'productName' => 'DELTA 2 Max', 'online' => 1 },
       { 'sn' => 'BBB2', 'productName' => 'RIVER 3', 'online' => 1 }]
    end

    def quota(sn, keys)
      raise EcoflowDashboard::Ecoflow::Client::Error, 'API 1006: not allowed' if sn == 'BBB2'

      # With the grid present the load runs through the station's input (bypass)
      { 'pd.soc' => 80, 'pd.wattsInSum' => grid ? out : 0, 'pd.wattsOutSum' => out,
        'bms_emsStatus.dsgRemainTime' => grid ? 5999 : 125, 'inv.acInVol' => grid ? 230_000 : 0,
        'bms_bmsStatus.remainCap' => 30_000, 'bms_bmsStatus.vol' => 54_000,
        'inv.acInFreq' => 50, 'inv.invOutVol' => 230_500,
        EcoflowDashboard::BatteryTrend::KEY => soc }.compact.slice(*keys).except(*missing)
    end

    def quota_all(_sn) = { 'pd.soc' => 80, 'inv.acInVol' => 230_000 }
  end
end
