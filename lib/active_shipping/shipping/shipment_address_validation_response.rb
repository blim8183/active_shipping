module ActiveMerchant
  module Shipping
    class AddressValidationResponse < Response

      attr_reader :status_code
      attr_reader :status_type
      attr_reader :addresses

      def initialize(success, message, params = {}, options = {})
        @addresses = []
        @status_type = options[:status_type]
        @status_code = options[:status_code]
        options[:addresses].each{ |address| @addresses << address } unless options[:addresses].blank?
        super
      end
    end
  end
end