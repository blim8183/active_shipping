# -*- encoding: utf-8 -*-

module ActiveMerchant
  module Shipping
    class UPSTradeAbility < Carrier
      SCHEMA = {
          :landed_cost => '../lib/schema/ups_international_service/LandedCost.wsdl',
          :export_license_detection => '../lib/schema/ups_international_service/ExportLicense.wsdl',
          :import_compliance => '../lib/schema/ups_international_service/ImportCompliance.wsdl',
          :denied_party_screening => '../lib/schema/ups_international_service/DeniedParty.wsdl'
      }

      def get_loading_cost(tariff_code, item_value, destination_country_code, destination_state_providence_code = nil)
        client = build_soap_client(:landed_cost)
        response = client.call(:process_lc_request, :message => build_landed_cost_request(tariff_code, item_value, destination_country_code, destination_state_providence_code))
        parse_landing_cost_response(response)
      end

      def build_soap_client(type)
        Savon.client(:wsdl => SCHEMA[type],
                     :namespaces => build_additional_namespaces,
                     :soap_header => build_access_request)
      end

      def parse_landing_cost_response(response)
        response.body[:landed_cost_response][:estimate_response][:shipment_estimate][:products_charges][:product][:charges]
      end

      def build_access_request
        {"upss:UPSSecurity" => {"upss:UsernameToken" => {"upss:Username" => @options[:login],
                                                         "upss:Password" => @options[:password]},
                                "upss:ServiceAccessToken" => {"upss:AccessLicenseNumber" => @options[:key]}}}
      end

      def build_additional_namespaces
        {"xmlns:upss" => "http://www.ups.com/XMLSchema/XOLTWS/UPSS/v1.0"}
      end

      def build_landed_cost_request(tariff_code, item_value, destination_country_code, destination_state_providence_code = nil)
        {"lc:Request" => {"lc:RequestAction" => "LandedCost"},
         "lc:QueryRequest" => {"lc:SuppressQuestionIndicator" => "Y",
                               "lc:Shipment" => {"lc:OriginCountryCode" => "US",
                                                 "lc:DestinationCountryCode" => destination_country_code,
                                                 "lc:DestinationStateProvinceCode" => destination_state_providence_code,
                                                 "lc:TransportationMode" => "1",
                                                 "lc:ResultCurrencyCode" => "USD",
                                                 "lc:Product" => {"lc:TariffInfo" => {"lc:TariffCode" => tariff_code},
                                                                  "lc:Quantity" => {"lc:Value" => "1"},
                                                                  "lc:UnitPrice" => {"lc:MonetaryValue" => item_value,
                                                                                     "lc:CurrencyCode" => "USD"}}}}}
      end
    end
  end
end