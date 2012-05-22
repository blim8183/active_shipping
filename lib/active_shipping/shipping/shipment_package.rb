module ActiveMerchant #:nodoc:
  module Shipping #:nodoc:
    class ShipmentPackage
      attr_reader :tracking_number
      attr_reader :label_image_format
      attr_reader :service_option_charges
      attr_reader :currency_code
      attr_reader :graphic_image
      attr_reader :html_image

      def initialize(tracking_number, label_image_format, graphic_image, html_image, options = {})
        @tracking_number = tracking_number
        @label_image_format = label_image_format
        @graphic_image = graphic_image
        @html_image = html_image
        @service_option_charges = options[:service_option_charges] unless options[:service_option_charges].blank?
        @currency_code = options[:currency_code] unless options[:currency_code]
      end
    end
  end
end