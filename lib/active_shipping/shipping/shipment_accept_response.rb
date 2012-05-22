module ActiveMerchant #:nodoc:
  module Shipping

    class ShipmentAcceptResponse < Response

      attr_reader :shipment_charges
      attr_reader :identification_number
      attr_reader :billing_weight
      attr_reader :weight_unit
      attr_reader :currency_code
      attr_reader :shipment_packages
      attr_reader :high_value_report_image
      attr_reader :high_value_report_image_format

      def initialize(success, message, params = {}, options = {})
        @shipment_packages = []
        @identification_number = options[:identification_number]
        @shipment_charges = options[:shipment_charges]
        @currency_code = options[:currency_code]
        @billing_weight = options[:billing_weight]
        @weight_unit = options[:weight_unit]
        unless options[:high_value_report_image].blank?
          @high_value_report_image = options[:high_value_report_image]
          @high_value_report_image_format = options[:high_value_report_image_format] || "HTML"
        end
        options[:shipment_packages].each{ |package| @shipment_packages << package }
        super
      end

    end

  end
end