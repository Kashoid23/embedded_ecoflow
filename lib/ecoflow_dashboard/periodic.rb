# frozen_string_literal: true

module EcoflowDashboard
  # Runs a block in a background thread every `seconds`. Errors are logged and the
  # loop keeps going, so one failed request doesn't stop data collection.
  module Periodic
    module_function

    def start(name, seconds, logger:)
      Thread.new do
        loop do
          begin
            yield
          rescue StandardError => e
            logger.warn("#{name}: #{e.class}: #{e.message}")
          end
          sleep seconds
        end
      end
    end
  end
end
