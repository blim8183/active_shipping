# -*- encoding: utf-8 -*-

module ActiveMerchant
  module Shipping
    class UPS < Carrier
      self.retry_safe = true

      cattr_accessor :default_options
      cattr_reader :name
      @@name = "UPS"

      TEST_URL = 'https://wwwcie.ups.com'
      LIVE_URL = 'https://onlinetools.ups.com'

      RESOURCES = {
          :rates => 'ups.app/xml/Rate',
          :track => 'ups.app/xml/Track',
          :shipment_confirm => 'ups.app/xml/ShipConfirm',
          :shipment_accept => 'ups.app/xml/ShipAccept',
          :void => 'ups.app/xml/Void',
          :address_validation => 'ups.app/xml/XAV'
      }

      PICKUP_CODES = HashWithIndifferentAccess.new({
                                                       :daily_pickup => "01",
                                                       :customer_counter => "03",
                                                       :one_time_pickup => "06",
                                                       :on_call_air => "07",
                                                       :suggested_retail_rates => "11",
                                                       :letter_center => "19",
                                                       :air_service_center => "20"
                                                   })

      CUSTOMER_CLASSIFICATIONS = HashWithIndifferentAccess.new({
                                                                   :wholesale => "01",
                                                                   :occasional => "03",
                                                                   :retail => "04"
                                                               })

      # these are the defaults described in the UPS API docs,
      # but they don't seem to apply them under all circumstances,
      # so we need to take matters into our own hands
      DEFAULT_CUSTOMER_CLASSIFICATIONS = Hash.new do |hash, key|
        hash[key] = case key.to_sym
                      when :daily_pickup then
                        :wholesale
                      when :customer_counter then
                        :retail
                      else
                        :occasional
                    end
      end

      DEFAULT_SERVICES = {
          "01" => "UPS Next Day Air",
          "02" => "UPS Second Day Air",
          "03" => "UPS Ground",
          "07" => "UPS Worldwide Express",
          "08" => "UPS Worldwide Expedited",
          "11" => "UPS Standard",
          "12" => "UPS Three-Day Select",
          "13" => "UPS Next Day Air Saver",
          "14" => "UPS Next Day Air Early A.M.",
          "54" => "UPS Worldwide Express Plus",
          "59" => "UPS Second Day Air A.M.",
          "65" => "UPS Saver",
          "82" => "UPS Today Standard",
          "83" => "UPS Today Dedicated Courier",
          "84" => "UPS Today Intercity",
          "85" => "UPS Today Express",
          "86" => "UPS Today Express Saver"
      }

      CANADA_ORIGIN_SERVICES = {
          "01" => "UPS Express",
          "02" => "UPS Expedited",
          "14" => "UPS Express Early A.M."
      }

      MEXICO_ORIGIN_SERVICES = {
          "07" => "UPS Express",
          "08" => "UPS Expedited",
          "54" => "UPS Express Plus"
      }

      EU_ORIGIN_SERVICES = {
          "07" => "UPS Express",
          "08" => "UPS Expedited"
      }

      OTHER_NON_US_ORIGIN_SERVICES = {
          "07" => "UPS Express"
      }

      # From http://en.wikipedia.org/w/index.php?title=European_Union&oldid=174718707 (Current as of November 30, 2007)
      EU_COUNTRY_CODES = ["GB", "AT", "BE", "BG", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"]

      US_TERRITORIES_TREATED_AS_COUNTRIES = ["AS", "FM", "GU", "MH", "MP", "PW", "PR", "VI"]

      CREDIT_CARD_TYPES = {
          "American Express" => "01",
          "Discover" => "03",
          "MasterCard" => "04",
          "Optima" => "05",
          "VISA" => "06",
          "Bravo" => "07",
          "Diners Club" => "08"
      }

      def requirements
        [:key, :login, :password]
      end

      def find_rates(origin, destination, packages, options={})
        origin, destination = upsified_location(origin), upsified_location(destination)
        options = @options.merge(options)
        packages = Array(packages)
        access_request = build_access_request
        rate_request = build_rate_request(origin, destination, packages, options)
        response = commit(:rates, save_request(access_request + rate_request), (options[:test] || false))
        parse_rate_response(origin, destination, packages, response, options)
      end

      def find_tracking_info(tracking_number, options={})
        options = @options.update(options)
        access_request = build_access_request
        tracking_request = build_tracking_request(tracking_number, options)
        response = commit(:track, save_request(access_request + tracking_request), (options[:test] || false))
        parse_tracking_response(response, options)
      end

      def build_confirmation_request(carrier_service, packages, label_specification, options)
        imperial = ['US', 'LR', 'MM'].include?(options[:origin][:country])
        packages = Array(packages)
        international = (packages[0] and packages[0].options[:products] and packages[0].options[:products].length > 0)
        xml_request = XmlNode.new('ShipmentConfirmRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'ShipConfirm')
            request << XmlNode.new('RequestOption', 'nonvalidate')
          end
          root_node << XmlNode.new('Shipment') do |shipment|
            if international
              shipment << XmlNode.new('Description', "Clothes and clothing accessories")
              if options[:destination][:country] == "CA"
                totalValue = 0
                packages.each do |package|
                  totalValue += package.value.to_s.to_i
                end
                shipment << XmlNode.new('InvoiceLineTotal') do |invoice_line_total|
                  invoice_line_total << XmlNode.new('CurrencyCode', "USD")
                  invoice_line_total << XmlNode.new('MonetaryValue', totalValue.to_s)
                end
              end
              shipment << XmlNode.new('ShipmentServiceOptions') do |service_options|
                service_options << XmlNode.new('InternationalForms') do |international_forms|
                  international_forms << XmlNode.new('FormType', "01")
                  international_forms << XmlNode.new('FormType', "03")
                  international_forms << XmlNode.new('FormType', "04")
                  international_forms << XmlNode.new('Contacts') do |contacts|
                    contacts << XmlNode.new('Producer') do |producer|
                      producer << XmlNode.new('Option', '02')
                    end
                  end
                  packages.each do |package|
                    package.options[:products].each do |product|
                      international_forms << XmlNode.new('Product') do |product_node|
                        product_node << XmlNode.new('Description', product[:description])
                        product_node << XmlNode.new('Unit') do |unit|
                          unit << XmlNode.new('Number', '1')
                          unit << XmlNode.new('UnitOfMeasurement') do |unit_of_measurement|
                            unit_of_measurement << XmlNode.new("Code", 'PC')
                          end
                          unit << XmlNode.new('Value', product[:value].to_s)
                        end
                        product_node << XmlNode.new('CommodityCode', product[:tariff_code])
                        product_node << XmlNode.new('PartNumber', "1")
                        product_node << XmlNode.new('OriginCountryCode', "US")
                        product_node << XmlNode.new('NetCostCode', "NO")
                        product_node << XmlNode.new('PreferenceCriteria', "B")
                        product_node << XmlNode.new('ProducerInfo', "No[1]")
                        product_node << XmlNode.new('NumberOfPackagesPerCommodity', "1")
                        product_node << XmlNode.new('ProductWeight') do |product_weight|
                          product_weight << XmlNode.new('UnitOfMeasurement') do |unit_of_measurement|
                            unit_of_measurement << XmlNode.new("Code", imperial ? 'LBS' : 'KGS')
                          end
                          product_weight << XmlNode.new("Weight", "3")
                        end
                      end
                    end
                  end
                  international_forms << XmlNode.new('InvoiceDate', Time.now.strftime("%Y%m%d"))
                  international_forms << XmlNode.new('ReasonForExport', "SALE")
                  international_forms << XmlNode.new('TermsOfShipment', "DDP")
                  international_forms << XmlNode.new('CurrencyCode', "USD")
                  international_forms << XmlNode.new('ExportDate', Time.now.strftime("%Y%m%d"))
                  international_forms << XmlNode.new('ExportingCarrier', "UPS")
                end
              end
            end
            shipment << XmlNode.new('Shipper') do |shipper|
              shipper << XmlNode.new("Name", options[:origin][:name])
              shipper << XmlNode.new("AttentionName", options[:origin][:attention_name]) unless options[:origin][:attention_name].blank?
              shipper << XmlNode.new("ShipperNumber", options[:origin][:origin_number])
              shipper << XmlNode.new("PhoneNumber", options[:origin][:phone]) unless options[:origin][:phone].blank?
              shipper << XmlNode.new("Address") do |address|
                address << XmlNode.new("AddressLine1", options[:origin][:address_line1])
                address << XmlNode.new("AddressLine2", options[:origin][:address_line2]) unless options[:origin][:address_line2].blank?
                address << XmlNode.new("AddressLine3", options[:origin][:address_line3]) unless options[:origin][:address_line3].blank?
                address << XmlNode.new("City", options[:origin][:city])
                address << XmlNode.new("StateProvinceCode", options[:origin][:state]) unless options[:origin][:state].blank?
                address << XmlNode.new("PostalCode", options[:origin][:zip]) unless options[:origin][:zip].blank?
                address << XmlNode.new("CountryCode", options[:origin][:country])
                address << XmlNode.new("ResidentialAddressIndicator", options[:origin][:residential_indicator]) unless options[:origin][:residential_indicator].blank?
              end
            end
            shipment << XmlNode.new('ShipTo') do |shipto|
              shipto << XmlNode.new("CompanyName", options[:destination][:company_name])
              shipto << XmlNode.new("AttentionName", options[:destination][:attention_name]) unless options[:destination][:attention_name].blank?
              shipto << XmlNode.new("PhoneNumber", options[:destination][:phone]) unless options[:destination][:phone].blank?
              shipto << XmlNode.new("Address") do |address|
                address << XmlNode.new("AddressLine1", options[:destination][:address_line1])
                address << XmlNode.new("AddressLine2", options[:destination][:address_line2]) unless options[:destination][:address_line2].blank?
                address << XmlNode.new("AddressLine3", options[:destination][:address_line3]) unless options[:destination][:address_line3].blank?
                address << XmlNode.new("City", options[:destination][:city])
                address << XmlNode.new("StateProvinceCode", options[:destination][:state]) unless options[:destination][:state].blank?
                address << XmlNode.new("PostalCode", options[:destination][:zip]) unless options[:destination][:zip].blank?
                address << XmlNode.new("CountryCode", options[:destination][:country])
                address << XmlNode.new("ResidentialAddressIndicator", options[:destination][:residential_indicator]) unless options[:destination][:residential_indicator].blank?
              end
            end

            shipment << XmlNode.new("SoldTo") do |sold_to|
              sold_to << XmlNode.new("CompanyName", options[:destination][:company_name])
              sold_to << XmlNode.new("AttentionName", options[:destination][:attention_name]) unless options[:destination][:attention_name].blank?
              sold_to << XmlNode.new("PhoneNumber", options[:destination][:phone]) unless options[:destination][:phone].blank?
              sold_to << XmlNode.new("Option", "01")
              sold_to << XmlNode.new("Address") do |address|
                address << XmlNode.new("AddressLine1", options[:destination][:address_line1])
                address << XmlNode.new("AddressLine2", options[:destination][:address_line2]) unless options[:destination][:address_line2].blank?
                address << XmlNode.new("AddressLine3", options[:destination][:address_line3]) unless options[:destination][:address_line3].blank?
                address << XmlNode.new("City", options[:destination][:city])
                address << XmlNode.new("StateProvinceCode", options[:destination][:state]) unless options[:destination][:state].blank?
                address << XmlNode.new("PostalCode", options[:destination][:zip]) unless options[:destination][:zip].blank?
                address << XmlNode.new("CountryCode", options[:destination][:country])
                address << XmlNode.new("ResidentialAddressIndicator", options[:destination][:residential_indicator]) unless options[:destination][:residential_indicator].blank?
              end
            end
            shipment << XmlNode.new('Service') do |shipment_service|
              shipment_service << XmlNode.new('Code', carrier_service || "14")
              shipment_service << XmlNode.new('Description', DEFAULT_SERVICES[carrier_service] || DEFAULT_SERVICES["14"])
            end

            if international
              shipment << XmlNode.new('ItemizedPaymentInformation') do |itemized_payment_information|
                itemized_payment_information << XmlNode.new('ShipmentCharge') do |shipment_charge|
                  shipment_charge << XmlNode.new('Type', '01')
                  shipment_charge << XmlNode.new('BillShipper') do |bill_shipper|
                    bill_shipper << XmlNode.new('AccountNumber', options[:origin][:origin_number])
                  end
                end
                itemized_payment_information << XmlNode.new('ShipmentCharge') do |shipment_charge|
                  shipment_charge << XmlNode.new('Type', '02')
                  shipment_charge << XmlNode.new('BillShipper') do |bill_shipper|
                    bill_shipper << XmlNode.new('AccountNumber', options[:origin][:origin_number])
                  end
                end
              end
            else
              shipment << XmlNode.new('PaymentInformation') do |payment_info|
                payment_info << XmlNode.new('Prepaid') do |prepaid|
                  prepaid << XmlNode.new('BillShipper') do |bill_shipper|
                    bill_shipper << XmlNode.new('AccountNumber', options[:origin][:origin_number])
                  end
                end
              end
            end

            packages.each do |package|
              shipment << XmlNode.new('Description', package.description) if package.description
              shipment << XmlNode.new("Package") do |package_node|
                package_node << XmlNode.new("PackagingType") do |packaging_type|
                  packaging_type << XmlNode.new("Code", '02')
                end
                package_node << XmlNode.new("Dimensions") do |dimensions|
                  dimensions << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'IN' : 'CM')
                  end
                  [:length, :width, :height].each do |axis|
                    value = ((imperial ? package.inches(axis) : package.cm(axis)).to_f*1000).round/1000.0 # 3 decimals
                    dimensions << XmlNode.new(axis.to_s.capitalize, [value, 0.1].max)
                  end
                end
                package_node << XmlNode.new("PackageWeight") do |package_weight|
                  package_weight << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'LBS' : 'KGS')
                  end
                  value = ((imperial ? package.lbs : package.kgs).to_f*1000).round/1000.0 # 3 decimals
                  package_weight << XmlNode.new("Weight", [value, 0.1].max)
                end
                unless package.value.blank?
                  package_node << XmlNode.new("PackageServiceOptions") do |package_service_options|
                    package_service_options << XmlNode.new("InsuredValue") do |insured_value|
                      currency = package.currency.blank? ? "USD" : package.currency.to_s
                      insured_value << XmlNode.new("CurrencyCode", currency)
                      insured_value << XmlNode.new("MonetaryValue", package.value.to_s)
                    end
                  end
                end
              end
            end
          end
          root_node << XmlNode.new('LabelSpecification') do |label|
            label << XmlNode.new('LabelPrintMethod') do |print_method|
              print_method << XmlNode.new('Code', label_specification[:print_code] || "GIF")
            end
            label << XmlNode.new('HTTPUserAgent', label_specification[:user_agent] || "Mozilla/4.5")
            label << XmlNode.new('LabelImageFormat') do |image_format|
              image_format << XmlNode.new('Code', label_specification[:format_code] || "GIF")
            end
          end
        end
        xml_request.to_s
      end

      def build_shipment_acceptance_request(digest, options)
        xml_request = XmlNode.new('ShipmentAcceptRequest') do |accept_request|
          accept_request << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'ShipAccept')
          end
          accept_request << XmlNode.new('ShipmentDigest', digest)
        end
        xml_request.to_s
      end

      def build_void_shipment_request(identification_number, tracking_numbers = [], options = {})
        xml_request = XmlNode.new('VoidShipmentRequest') do |void_request|
          void_request << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Void')
            request << XmlNode.new('RequestOption', '1')
          end

          if tracking_numbers.blank?
            void_request << XmlNode.new('ShipmentIdentificationNumber', identification_number)
          else
            void_request << XmlNode.new('ExpandedVoidShipment') do |expanded_void_shipment|
              expanded_void_shipment << XmlNode.new('ShipmentIdentificationNumber', identification_number)
              tracking_numbers.each do |tracking_number|
                expanded_void_shipment << XmlNode.new('TrackingNumber', tracking_number)
              end
            end
          end
        end
        xml_request.to_s
      end

      def build_validate_address_request(address, options)
        xml_request = XmlNode.new('AddressValidationRequest') do |address_request|
          address_request << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'XAV')
          end

          address_request << XmlNode.new('AddressKeyFormat') do |request|
            request << XmlNode.new("AddressLine", address[:address_line_1])
            request << XmlNode.new("AddressLine", address[:address_line_2])
            request << XmlNode.new("PoliticalDivision2", address[:city])
            request << XmlNode.new("PoliticalDivision1", address[:state])
            request << XmlNode.new("PostcodePrimaryLow", address[:zip])
            request << XmlNode.new("CountryCode", address[:country])
          end
        end
        xml_request.to_s
      end

      def shipment_confirmation_request(carrier_service, packages, label_specification, options)
        options = @options.merge(options)
        packages = Array(packages)
        access_request = "<?xml version='1.0' ?>" + build_access_request
        confirmation_request = "<?xml version='1.0' encoding='UTF-8' ?>" + build_confirmation_request(carrier_service, packages, label_specification, options)
        response = commit(:shipment_confirm, save_request(access_request + confirmation_request), (options[:test] || false))
        parse_shipment_confirm_response(response, options)
      end

      def shipment_accept_request(digest, options = {})
        options = @options.merge(options)
        access_request = "<?xml version='1.0' ?>" + build_access_request
        acceptance_request = "<?xml version='1.0' encoding='UTF-8' ?>" + build_shipment_acceptance_request(digest, options)
        response = commit(:shipment_accept, save_request(access_request + acceptance_request), (options[:test] || false))
        parse_shipment_accept_response(response, options)
      end

      def void_shipment(identification_number, tracking_numbers = [], options = {})
        options = @options.merge(options)
        tracking_numbers = Array(tracking_numbers)
        access_request = "<?xml version='1.0' ?>" + build_access_request
        void_request = "<?xml version='1.0' encoding='UTF-8' ?>" + build_void_shipment_request(identification_number, tracking_numbers, options)
        response = commit(:void, save_request(access_request + void_request), (options[:test] || false))
        parse_void_response(response, options)
      end

      def validate_address(address, options = {})
        options = @options.merge(options)
        access_request = "<?xml version='1.0' ?>" + build_access_request
        validation_request = "<?xml version='1.0' encoding='UTF-8' ?>" + build_validate_address_request(address, options)
        response = commit(:address_validation, save_request(access_request + validation_request), (options[:test] || false))
        parse_address_validation_response(response, options)
      end

      protected

      def upsified_location(location)
        if location.country_code == 'US' && US_TERRITORIES_TREATED_AS_COUNTRIES.include?(location.state)
          atts = {:country => location.state}
          [:zip, :city, :address1, :address2, :address3, :phone, :fax, :address_type].each do |att|
            atts[att] = location.send(att)
          end
          Location.new(atts)
        else
          location
        end
      end

      def build_access_request
        xml_request = XmlNode.new('AccessRequest') do |access_request|
          access_request << XmlNode.new('AccessLicenseNumber', @options[:key])
          access_request << XmlNode.new('UserId', @options[:login])
          access_request << XmlNode.new('Password', @options[:password])
        end
        xml_request.to_s
      end

      def build_rate_request(origin, destination, packages, options={})
        packages = Array(packages)
        xml_request = XmlNode.new('RatingServiceSelectionRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Rate')
            request << XmlNode.new('RequestOption', 'Shop')
            # not implemented: 'Rate' RequestOption to specify a single service query
            # request << XmlNode.new('RequestOption', ((options[:service].nil? or options[:service] == :all) ? 'Shop' : 'Rate'))
          end

          pickup_type = options[:pickup_type] || :daily_pickup

          root_node << XmlNode.new('PickupType') do |pickup_type_node|
            pickup_type_node << XmlNode.new('Code', PICKUP_CODES[pickup_type])
            # not implemented: PickupType/PickupDetails element
          end
          cc = options[:customer_classification] || DEFAULT_CUSTOMER_CLASSIFICATIONS[pickup_type]
          root_node << XmlNode.new('CustomerClassification') do |cc_node|
            cc_node << XmlNode.new('Code', CUSTOMER_CLASSIFICATIONS[cc])
          end

          root_node << XmlNode.new('Shipment') do |shipment|
            # not implemented: Shipment/Description element
            shipment << build_location_node('Shipper', (options[:shipper] || origin), options)
            shipment << build_location_node('ShipTo', destination, options)
            if options[:shipper] and options[:shipper] != origin
              shipment << build_location_node('ShipFrom', origin, options)
            end

            # not implemented:  * Shipment/ShipmentWeight element
            #                   * Shipment/ReferenceNumber element                    
            #                   * Shipment/Service element                            
            #                   * Shipment/PickupDate element                         
            #                   * Shipment/ScheduledDeliveryDate element              
            #                   * Shipment/ScheduledDeliveryTime element              
            #                   * Shipment/AlternateDeliveryTime element              
            #                   * Shipment/DocumentsOnly element                      

            packages.each do |package|
              imperial = ['US', 'LR', 'MM'].include?(origin.country_code(:alpha2))

              shipment << XmlNode.new("Package") do |package_node|

                # not implemented:  * Shipment/Package/PackagingType element
                #                   * Shipment/Package/Description element

                package_node << XmlNode.new("PackagingType") do |packaging_type|
                  packaging_type << XmlNode.new("Code", '02')
                end

                package_node << XmlNode.new("Dimensions") do |dimensions|
                  dimensions << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'IN' : 'CM')
                  end
                  [:length, :width, :height].each do |axis|
                    value = ((imperial ? package.inches(axis) : package.cm(axis)).to_f*1000).round/1000.0 # 3 decimals
                    dimensions << XmlNode.new(axis.to_s.capitalize, [value, 0.1].max)
                  end
                end

                package_node << XmlNode.new("PackageWeight") do |package_weight|
                  package_weight << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'LBS' : 'KGS')
                  end

                  value = ((imperial ? package.lbs : package.kgs).to_f*1000).round/1000.0 # 3 decimals
                  package_weight << XmlNode.new("Weight", [value, 0.1].max)
                end

                unless package.value.blank?
                  package_node << XmlNode.new("PackageServiceOptions") do |package_service_options|
                    package_service_options << XmlNode.new("InsuredValue") do |insured_value|
                      currency = package.currency.blank? ? "USD" : package.currency.to_s
                      insured_value << XmlNode.new("CurrencyCode", currency)
                      insured_value << XmlNode.new("MonetaryValue", package.value.to_s)
                    end
                  end
                end

                # not implemented:  * Shipment/Package/LargePackageIndicator element
                #                   * Shipment/Package/ReferenceNumber element
                #                   * Shipment/Package/PackageServiceOptions element
                #                   * Shipment/Package/AdditionalHandling element  
              end

            end

            # not implemented:  * Shipment/ShipmentServiceOptions element
            #                   * Shipment/RateInformation element

          end

        end
        xml_request.to_s
      end

      def build_tracking_request(tracking_number, options={})
        xml_request = XmlNode.new('TrackRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Track')
            request << XmlNode.new('RequestOption', '1')
          end
          root_node << XmlNode.new('TrackingNumber', tracking_number.to_s)
        end
        xml_request.to_s
      end

      def build_location_node(name, location, options={})
        # not implemented:  * Shipment/Shipper/Name element
        #                   * Shipment/(ShipTo|ShipFrom)/CompanyName element
        #                   * Shipment/(Shipper|ShipTo|ShipFrom)/AttentionName element
        #                   * Shipment/(Shipper|ShipTo|ShipFrom)/TaxIdentificationNumber element
        location_node = XmlNode.new(name) do |location_node|
          location_node << XmlNode.new('PhoneNumber', location.phone.gsub(/[^\d]/, '')) unless location.phone.blank?
          location_node << XmlNode.new('FaxNumber', location.fax.gsub(/[^\d]/, '')) unless location.fax.blank?

          if name == 'Shipper' and (origin_account = @options[:origin_account] || options[:origin_account])
            location_node << XmlNode.new('ShipperNumber', origin_account)
          elsif name == 'ShipTo' and (destination_account = @options[:destination_account] || options[:destination_account])
            location_node << XmlNode.new('ShipperAssignedIdentificationNumber', destination_account)
          end

          location_node << XmlNode.new('Address') do |address|
            address << XmlNode.new("AddressLine1", location.address1) unless location.address1.blank?
            address << XmlNode.new("AddressLine2", location.address2) unless location.address2.blank?
            address << XmlNode.new("AddressLine3", location.address3) unless location.address3.blank?
            address << XmlNode.new("City", location.city) unless location.city.blank?
            address << XmlNode.new("StateProvinceCode", location.province) unless location.province.blank?
            # StateProvinceCode required for negotiated rates but not otherwise, for some reason
            address << XmlNode.new("PostalCode", location.postal_code) unless location.postal_code.blank?
            address << XmlNode.new("CountryCode", location.country_code(:alpha2)) unless location.country_code(:alpha2).blank?
            address << XmlNode.new("ResidentialAddressIndicator", true) unless location.commercial? # the default should be that UPS returns residential rates for destinations that it doesn't know about
                                                                                                    # not implemented: Shipment/(Shipper|ShipTo|ShipFrom)/Address/ResidentialAddressIndicator element
          end
        end
      end

      def parse_rate_response(origin, destination, packages, response, options={})
        rates = []

        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)

        if success
          rate_estimates = []

          xml.elements.each('/*/RatedShipment') do |rated_shipment|
            service_code = rated_shipment.get_text('Service/Code').to_s
            days_to_delivery = rated_shipment.get_text('GuaranteedDaysToDelivery').to_s.to_i
            delivery_date = days_to_delivery >= 1 ? days_to_delivery.days.from_now.strftime("%Y-%m-%d") : nil

            rate_estimates << RateEstimate.new(origin, destination, @@name,
                                               service_name_for(origin, service_code),
                                               :total_price => rated_shipment.get_text('TotalCharges/MonetaryValue').to_s.to_f,
                                               :currency => rated_shipment.get_text('TotalCharges/CurrencyCode').to_s,
                                               :service_code => service_code,
                                               :packages => packages,
                                               :delivery_range => [delivery_date])
          end
        end
        RateResponse.new(success, message, Hash.from_xml(response).values.first, :rates => rate_estimates, :xml => response, :request => last_request)
      end

      def parse_shipment_confirm_response(response, options = {})
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)

        if success
          root_node = xml.elements['ShipmentConfirmResponse']
          identification_number = root_node.get_text('ShipmentIdentificationNumber').to_s
          total_price = root_node.get_text('TotalCharges/MonetaryValue').to_s.to_f
          currency = root_node.get_text('TotalCharges/CurrencyCode').to_s
          digest = root_node.get_text('ShipmentDigest').to_s
        end

        ShipmentConfirmResponse.new(success, message, Hash.from_xml(response).values.first,
                                    :xml => response,
                                    :request => last_request,
                                    :identification_number => identification_number,
                                    :total_price => total_price,
                                    :currency => currency,
                                    :digest => digest
        )
      end

      def parse_shipment_accept_response(response, options = {})
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)

        if success
          @shipment_packages = []
          xml.elements.each('/*/*/PackageResults') do |package_result|
            tracking_number = package_result.get_text('TrackingNumber').to_s
            service_option_charges = package_result.get_text('ServiceOptionsCharges/MonetaryValue').to_s.to_f
            service_option_charges_currency = package_result.get_text('ServiceOptionsCharges/CurrencyCode').to_s
            label_image_format = package_result.get_text('LabelImage/LabelImageFormat/Code').to_s
            graphic_image = package_result.get_text('LabelImage/GraphicImage').to_s
            html_image = package_result.get_text('LabelImage/HTMLImage').to_s
            @shipment_packages << ShipmentPackage.new(tracking_number, label_image_format, graphic_image, html_image, {:service_option_charges => service_option_charges, :currency_code => service_option_charges_currency})
          end

          root_node = xml.elements['ShipmentAcceptResponse/ShipmentResults']
          identification_number = root_node.get_text('ShipmentIdentificationNumber').to_s
          shipment_charges = root_node.get_text('ShipmentCharges/TotalCharges/MonetaryValue').to_s.to_f
          currency_code = root_node.get_text('ShipmentCharges/TotalCharges/CurrencyCode').to_s
          billing_weight = root_node.get_text('BillingWeight/Weight').to_s.to_f
          weight_unit = root_node.get_text('BillingWeight/UnitOfMeasurement/Code').to_s
          high_value_report_node = root_node.elements['ControlLogReceipt']

          if high_value_report_node
            high_value_report_image = high_value_report_node.get_text('GraphicImage').to_s
            high_value_report_image_format = high_value_report_node.get_text('ImageFormat/Code').to_s
          end
        end

        ShipmentAcceptResponse.new(success, message, Hash.from_xml(response).values.first,
                                   :xml => response,
                                   :request => last_request,
                                   :identification_number => identification_number,
                                   :shipment_charges => shipment_charges,
                                   :currency_code => currency_code,
                                   :billing_weight => billing_weight,
                                   :weight_unit => weight_unit,
                                   :high_value_report_image => high_value_report_image,
                                   :high_value_report_image_format => high_value_report_image_format,
                                   :shipment_packages => @shipment_packages
        )
      end

      def parse_void_response(response, options = {})
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)

        if success
          @package_level_results = []
          xml.elements.each('/*/PackageLevelResults') do |package_level_result|
            tracking_number = package_level_result.get_text('TrackingNumber').to_s
            status_code = package_level_result.get_text('StatusCode').to_s.to_f
            description = package_level_result.get_text('Description').to_s
            @package_level_results << VoidResult.new(tracking_number, status_code, description)
          end

          status_node = xml.elements['VoidShipmentResponse/Status']
          status_type = status_node.get_text('StatusType/Code').to_s
          status_code = status_node.get_text('StatusCode/Code').to_s
        end

        VoidShipmentResponse.new(success, message, Hash.from_xml(response).values.first,
                                 :xml => response,
                                 :request => last_request,
                                 :package_level_results => @package_level_results,
                                 :status_type => status_type,
                                 :status_code => status_code
        )
      end

      def parse_address_validation_response(response, options={})
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)

        if success
          @addresses = []
          xml.elements.each('/*/AddressKeyFormat') do |address|
            addresses_lines = address.get_elements('AddressLine')
            address_first = addresses_lines.slice!(0)
            address_second = addresses_lines.slice!(0)

            address1 = address_first.text if address_first
            address_second ? address2 = address_second.text : address2 = ""
            city = address.get_text('PoliticalDivision2').to_s
            province = address.get_text('PoliticalDivision1').to_s
            postal_code = address.get_text('PostcodePrimaryLow').to_s
            country = address.get_text('CountryCode').to_s
            @addresses << Location.new(:address1 => address1,
                                       :address2 => address2,
                                       :city => city,
                                       :province => province,
                                       :postal_code => postal_code,
                                       :country => country)
          end
        end
        AddressValidationResponse.new(success, message, Hash.from_xml(response),
                                      :xml => response,
                                      :request => last_request,
                                      :addresses => @addresses
        )
      end

      def parse_tracking_response(response, options={})
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)

        if success
          tracking_number, origin, destination, status_code, status_description = nil
          delivered, exception = false
          exception_event = nil
          shipment_events = []
          status = {}
          scheduled_delivery_date = nil

          first_shipment = xml.elements['/*/Shipment']
          first_package = first_shipment.elements['Package']
          tracking_number = first_shipment.get_text('ShipmentIdentificationNumber | Package/TrackingNumber').to_s

          # Build status hash
          status_node = first_package.elements['Activity/Status/StatusType']
          status_code = status_node.get_text('Code').to_s
          status_description = status_node.get_text('Description').to_s
          status = TRACKING_STATUS_CODES[status_code]

          if status_description =~ /out.*delivery/i
            status = :out_for_delivery
          end

          origin, destination = %w{Shipper ShipTo}.map do |location|
            location_from_address_node(first_shipment.elements["#{location}/Address"])
          end

          # Get scheduled delivery date
          unless status == :delivered
            scheduled_delivery_date = parse_ups_datetime({
                                                           :date => first_shipment.get_text('ScheduledDeliveryDate'),
                                                           :time => nil
                                                         })
          end

          activities = first_package.get_elements('Activity')
          unless activities.empty?
            shipment_events = activities.map do |activity|
              description = activity.get_text('Status/StatusType/Description').to_s
              zoneless_time = if (time = activity.get_text('Time')) &&
                (date = activity.get_text('Date'))
                                time, date = time.to_s, date.to_s
                                hour, minute, second = time.scan(/\d{2}/)
                                year, month, day = date[0..3], date[4..5], date[6..7]
                                Time.utc(year, month, day, hour, minute, second)
                              end
              location = location_from_address_node(activity.elements['ActivityLocation/Address'])
              ShipmentEvent.new(description, zoneless_time, location)
            end

            shipment_events = shipment_events.sort_by(&:time)

            # UPS will sometimes archive a shipment, stripping all shipment activity except for the delivery
            # event (see test/fixtures/xml/delivered_shipment_without_events_tracking_response.xml for an example).
            # This adds an origin event to the shipment activity in such cases.
            if origin && !(shipment_events.count == 1 && status == :delivered)
              first_event = shipment_events[0]
              same_country = origin.country_code(:alpha2) == first_event.location.country_code(:alpha2)
              same_or_blank_city = first_event.location.city.blank? or first_event.location.city == origin.city
              origin_event = ShipmentEvent.new(first_event.name, first_event.time, origin)
              if same_country and same_or_blank_city
                shipment_events[0] = origin_event
              else
                shipment_events.unshift(origin_event)
              end
            end

            # Has the shipment been delivered?
            if status == :delivered
              if !destination
                destination = shipment_events[-1].location
              end
              shipment_events[-1] = ShipmentEvent.new(shipment_events.last.name, shipment_events.last.time, destination)
            end
          end

        end
        TrackingResponse.new(success, message, Hash.from_xml(response).values.first,
                             :carrier => @@name,
                             :xml => response,
                             :request => last_request,
                             :status => status,
                             :status_code => status_code,
                             :status_description => status_description,
                             :scheduled_delivery_date => scheduled_delivery_date,
                             :shipment_events => shipment_events,
                             :delivered => delivered,
                             :exception => exception,
                             :exception_event => exception_event,
                             :origin => origin,
                             :destination => destination,
                             :tracking_number => tracking_number)
      end

      def location_from_address_node(address)
        return nil unless address
        Location.new(
            :country => node_text_or_nil(address.elements['CountryCode']),
            :postal_code => node_text_or_nil(address.elements['PostalCode']),
            :province => node_text_or_nil(address.elements['StateProvinceCode']),
            :city => node_text_or_nil(address.elements['City']),
            :address1 => node_text_or_nil(address.elements['AddressLine1']),
            :address2 => node_text_or_nil(address.elements['AddressLine2']),
            :address3 => node_text_or_nil(address.elements['AddressLine3'])
        )
      end

      def parse_ups_datetime(options = {})
        time, date = options[:time].to_s, options[:date].to_s
        if time.nil?
          hour, minute, second = 0
        else
          hour, minute, second = time.scan(/\d{2}/)
        end
        year, month, day = date[0..3], date[4..5], date[6..7]

        Time.utc(year, month, day, hour, minute, second)
      end

      def response_success?(xml)
        xml.get_text('/*/Response/ResponseStatusCode').to_s == '1'
      end

      def response_message(xml)
        xml.get_text('/*/Response/Error/ErrorDescription | /*/Response/ResponseStatusDescription').to_s
      end

      def commit(action, request, test = false)
        ssl_post("#{test ? TEST_URL : LIVE_URL}/#{RESOURCES[action]}", request)
      end


      def service_name_for(origin, code)
        origin = origin.country_code(:alpha2)

        name = case origin
                 when "CA" then
                   CANADA_ORIGIN_SERVICES[code]
                 when "MX" then
                   MEXICO_ORIGIN_SERVICES[code]
                 when *EU_COUNTRY_CODES then
                   EU_ORIGIN_SERVICES[code]
               end

        name ||= OTHER_NON_US_ORIGIN_SERVICES[code] unless name == 'US'
        name ||= DEFAULT_SERVICES[code]
      end

    end
  end
end
