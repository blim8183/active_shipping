$:.unshift(File.dirname(__FILE__) + '/../lib')

require 'base64'
require 'fileutils'
require 'tempfile'
require 'active_shipping'

class UpsLabelTest
  include ActiveMerchant::Shipping

  UPS_ORIGIN_NUMBER = "xxxxx"
  UPS_LOGIN = 'xxxxx'
  UPS_PASSWORD = 'xxxxx'
  UPS_KEY = 'xxxxx'

  TESTING = true
  SAVE_LABEL_LOCATION = "#{Dir.home}/Downloads/ups"

  # services located in UPS::DEFAULT_SERVICES
  #
  # "01" => "UPS Next Day Air",
  # "02" => "UPS Second Day Air",
  # "03" => "UPS Ground",
  # "07" => "UPS Worldwide Express",
  # "08" => "UPS Worldwide Expedited",
  # "11" => "UPS Standard",
  # "12" => "UPS Three-Day Select",
  # "13" => "UPS Next Day Air Saver",
  # "14" => "UPS Next Day Air Early A.M.",
  # "54" => "UPS Worldwide Express Plus",
  # "59" => "UPS Second Day Air A.M.",
  # "65" => "UPS Saver",
  # "82" => "UPS Today Standard",
  # "83" => "UPS Today Dedicated Courier",
  # "84" => "UPS Today Intercity",
  # "85" => "UPS Today Express",
  # "86" => "UPS Today Express Saver"

  def initialize
    @ups = UPS.new(:login => UPS_LOGIN, :password => UPS_PASSWORD, :key => UPS_KEY, :test => true)
  end

  #end method initialize
  def run_tests
    [:domestic, :international].each do |destination_type|
      puts "\nRUNNING TESTS FOR #{destination_type.to_s.upcase} DESTINATION\n\n"
      UPS::DEFAULT_SERVICES.keys.sort.each do |code|
        begin
          trk_num = run_test_for_service(code, destination_type)
          puts "Generated label for: #{UPS::DEFAULT_SERVICES[code]} => #{trk_num}"
        rescue => e
          puts "ERROR GENERATING: #{UPS::DEFAULT_SERVICES[code]} => #{e.message}"
        end
      end
    end
    puts "\nTESTING ADDRESS VALIDATION\n\n"
    address = { :address_line_1 => "18740 Lisburn Pl",
                :city => "Northridge",
                :state => "CA",
                :zip => "984134",
                :country => "US"
    }
    @ups.validate_address(address)
  end

  #end method run_tests


  def get_packages
    #please refer Package class (lib/shipping/package.rb) for more info
    [
        Package.new((3 * 16), [12, 12, 12], :units => :imperial, :description => "Earrings")
    ]
  end

  #end method get_packages


  def get_label_specification
    # Label print method code that the labels are to be generated for EPL2 formatted
    # labels use EPL, for SPL formatted labels use SPL, for ZPL formatted labels use ZPL,
    # for STAR printer formatted labels use STARPL and for image formats use GIF.

    {:print_code => "GIF", :format_code => "GIF", :user_agent => "Mozilla/4.5"}
  end

  #end method label_specification


  def get_options
    #create a options hash containing origin, destination. For test environment pass :test => true
    origin = {
        :address_line1 => "788 Harrison Street",
        :address_line2 => "Apt 417",
        :country => 'US',
        :state => 'CA',
        :city => 'San fsdfs',
        :zip => '91245',
        :phone => "(818) 321-8833",
        :name => "Andy Shin",
        :attention_name => "Andy Shin",
        :origin_number => UPS_ORIGIN_NUMBER
    }

    options = {
        :domestic => {
            :origin => origin,
            :destination => {
                :company_name => "Kay Shin",
                :attention_name => "Kay Shin",
                :phone => "(818) 366-6001",
                :address_line1 => "18740 Lisburn Place",
                :country => 'US',
                :state => 'CA',
                :city => 'Northridge',
                :zip => '91326'
            },
            :test => TESTING
        },
        :international => {
            :origin => origin,
            :destination => {
                :company_name => "David Beckham",
                :attention_name => "David Beckham",
                :phone => "+555555555555",
                :address_line1 => "47 KENDAL Street",
                :country => 'GB',
                :state => 'UK',
                :city => 'LONDON',
                :zip => 'W2 2BU'
            },
            :test => TESTING
        }
    }
  end

  #end method get_options


  def create_confirm_response(carrier_service, packages, label_specification, options)
    #send the Shipment Confirm Request and catch the response. if successful then it will return an identification number, shipment charges and a shipment digest.
    @confirm_response = @ups.shipment_confirmation_request(carrier_service, packages, label_specification, options)
  end

  #end method create_confirm_response


  def create_shipment_request(confirm_response)
    #send the Shipment Accept Request and catch the response. if successful then it will return tracking number, base64 html label, base64 graphic label for each package and identification number for the shipment.
    @accept_response = @ups.shipment_accept_request(confirm_response.digest, {:test => TESTING})
  end

  #end method create_shipment_request(confirm_response)


  def run_test_for_service(carrier_service, destination_type=:domestic)
    packages = get_packages
    label_specification = get_label_specification
    options = get_options

    confirm_response = create_confirm_response(carrier_service, packages, label_specification, options[destination_type])
    accept_response = create_shipment_request(confirm_response)

    return get_label_and_other_info(accept_response)
  end #end run_test_for_service

  def get_label_and_other_info(accept_response)
    #To get label and other info of each package of the above shipment
    accept_response.shipment_packages.each do |package|

      #gives you the base64 code for html label
      html_image = package.html_image

      #gives you the base64 code for graphic label
      graphic_image = package.graphic_image

      #gives you the images format(gif/png)
      label_image_format = package.label_image_format

      #gives you the tracking number of package
      tracking_number = package.tracking_number

      #write out the GRAPHIC file
      label_tmp_file = Tempfile.new("shipping_label")
      label_tmp_file.write Base64.decode64(graphic_image)
      label_tmp_file.rewind

      #write out the HTML file
      html_tmp_file = Tempfile.new("shipping_label_html")
      html_tmp_file.write Base64.decode64(html_image)
      html_tmp_file.rewind

      #save the GRAPHIC file
      graphic_filename = "#{SAVE_LABEL_LOCATION}/label#{tracking_number}.#{label_image_format.downcase}"
      gf = File.new(graphic_filename, "wb")
      gf.write File.new(label_tmp_file.path).read
      gf.close

      #save the HTML file
      html_filename = "#{SAVE_LABEL_LOCATION}/#{tracking_number}.html"
      hf = File.new(html_filename, "wb")
      hf.write File.new(html_tmp_file.path).read
      hf.close

      return tracking_number
    end #end accept_response.shipment_packages.each
  end #end get_label_and_other_info
end #end class


test = UpsLabelTest.new
test.run_tests # <== Now go check your folder
