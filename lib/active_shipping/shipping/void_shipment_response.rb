module ActiveMerchant
  module Shipping
    class VoidShipmentResponse < Response

      attr_reader :status_code
      attr_reader :status_type
      attr_reader :package_level_results

      def initialize(success, message, params = {}, options = {})
        @package_level_results = []
        @status_type = options[:status_type]
        @status_code = options[:status_code]
        options[:package_level_results].each{ |result| @package_level_results << result } unless options[:package_level_results].blank?
        super
      end

    end

  end
end