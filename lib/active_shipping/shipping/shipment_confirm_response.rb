module ActiveMerchant #:nodoc:
  module Shipping

    class ShipmentConfirmResponse < Response

      attr_reader :digest
      attr_reader :identification_number
      attr_reader :total_price
      attr_reader :currency

      def initialize(success, message, params = {}, options = {})
        @identification_number = options[:identification_number]
        @digest = options[:digest]
        @total_price = options[:total_price]
        @currency = options[:currency]
        super
      end

    end

  end
end