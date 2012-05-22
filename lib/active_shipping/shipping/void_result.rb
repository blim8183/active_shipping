module ActiveMerchant #:nodoc:
  module Shipping #:nodoc:
    class VoidResult
      attr_reader :tracking_number
      attr_reader :status_code
      attr_reader :description

      def initialize(tracking_number, status_code, description, options = {})
        @tracking_number = tracking_number
        @status_code = status_code
        @description = description
      end
    end
  end
end