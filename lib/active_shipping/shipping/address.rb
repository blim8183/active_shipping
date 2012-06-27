module ActiveMerchant #:nodoc:
  module Shipping #:nodoc:
    class UPSAddress

      attr_reader :address1
      attr_reader :address2
      attr_reader :city
      attr_reader :province
      attr_reader :postal_code
      attr_reader :country

      def initialize(address1, address2, city, province, postal_code, country, options = {})
        @address1 = address1
        @address2 = address2
        @city = city
        @province = province
        @postal_code = postal_code
        @country = country
      end
    end
  end
end