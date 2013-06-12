$:.unshift(File.dirname(__FILE__) + '/../lib')

require 'base64'
require 'fileutils'
require 'tempfile'
require 'active_shipping'

class TradeAbilityTest
  include ActiveMerchant::Shipping

  TESTING = true

  def initialize
    @ups = UPSTradeAbility.new(:login => UPS_LOGIN, :password => UPS_PASSWORD, :key => UPS_KEY, :test => TESTING)
  end

  #end method initialize
  def run_tests
    landed_cost = @ups.get_loading_cost("6206.20.0000", "300", "CA", "QC")
    print landed_cost
  end
end #end class


test = TradeAbilityTest.new
test.run_tests # <== Now go check your folder