require 'rexml/document'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class SecurePayAuGateway < Gateway
      API_VERSION = 'xml-4.2'
      
      TEST_URL = 'https://test.securepay.com.au/xmlapi'
      LIVE_URL = 'https://www.securepay.com.au/xmlapi'
      
      self.supported_countries = ['AU']
      self.supported_cardtypes = [:visa, :master, :american_express, :diners_club, :jcb]
      
      # The homepage URL of the gateway
      self.homepage_url = 'http://securepay.com.au'
      
      # The name of the gateway
      self.display_name = 'SecurePay'
      
      class_inheritable_accessor :request_timeout
      self.request_timeout = 60
      
      self.money_format = :cents
      self.default_currency = 'AUD'
      
      # 0 Standard Payment
      # 4 Refund 
      # 6 Client Reversal (Void) 
      # 10 Preauthorise 
      # 11 Preauth Complete (Advice)        
      TRANSACTIONS = {
        :purchase => 0,
        :authorization => 10,
        :capture => 11,
        :void => 6,
        :credit => 4,
        :recurring => 14
      }

      SUCCESS_CODES = [ '00', '08', '11', '16', '77' ]
      
      # Recuring payments
      RECURRING_ACTIONS = ['add', 'delete', 'trigger']
      
      RECURRING_INTERVALS = {
        :weekly => 1,
        :biweekly => 2,
        :monthly => 3,
        :quarterly => 4,
        :halfyearly => 5,
        :yearly => 6
      }

      def initialize(options = {})
        requires!(options, :login, :password)
        @options = options
        super
      end
      
      def test?
        @options[:test] || super
      end
      
      def purchase(money, credit_card, options = {})
        commit :purchase, build_purchase_request(:purchase, money, credit_card, options)
      end                       

      # Create a recuring payment
      # Sees:  http://www.securepay.com.au/resources/Secure-XML-API/Integration-Guide-Periodic-and-Triggered-add-in-pg01.html
      # * <tt>starting_at</tt> - Start date of the recurring payment
      # * <tt>profile_id</tt> - Client reference id
      # * <tt>name</tt> - The name of the customer to be billed.  If not specified, the name from the credit card is used.
      # * <tt>periodicity</tt> - The frequency that the recurring payments will occur at.  Can be one of
      # :weekly, :biweekly, :monthly, :semimonthly, :quarterly, :semiyearly, :yearly
      # * <tt>payments</tt> - The term, or number of payments that will be made
      def recurring(money, credit_card, options = {})
        requires!(options, [:periodicity, :monthly, :weekly, :daily], :payments, :profile_id)
        
        request = build_recurring_request('add', money, credit_card, options)
        commit :recurring, request
      end
    
      def cancel_recurring(profile_id, options = {})
        requires!(options, :profile_id)

        options[:profile_id] = profile_id
        request = build_recurring_request('delete', nil, nil, options)
        commit :recurring, request
      end
      
      private
      
      def build_recurring_request(action, money, credit_card, options)
        unless RECURRING_ACTIONS.include?(action)
          raise StandardError, "Invalid Recurring Profile Action: #{action}"
        end
        
        periodicity = options[:periodicity]
        xml = Builder::XmlMarkup.new
        
        xml.tag! 'RequestType', 'Periodic'
        xml.tag! 'Periodic' do
          xml.tag! 'PeriodicList', "count" => 1 do
            xml.tag! 'PeriodicItem', "ID" => 1 do
              xml.tag! 'actionType', action
              xml.tag! 'clientID', options[:profile_id]
              
              if action == 'add'
                xml.tag! 'amount', amount(money)
                xml.tag! 'startDate', (options[:starting_at] || Date.today).strftime('%Y%m%d')
                xml.tag! 'periodicType', 3
                xml.tag! 'paymentInterval', RECURRING_INTERVALS[periodicity]
                xml.tag! 'numberOfPayments', options[:payments]
                add_credit_card(xml, credit_card)
              end
            end
          end
        end
      end
      
      def build_purchase_request(action, money, credit_card, options)
        xml = Builder::XmlMarkup.new

        xml.tag! 'RequestType', 'Payment'
        xml.tag! 'Payment' do
          xml.tag! 'TxnList', "count" => 1 do
            xml.tag! 'Txn', "ID" => 1 do
              xml.tag! 'txnType', TRANSACTIONS[action]
              xml.tag! 'txnSource', 23
              
              xml.tag! 'amount', amount(money)
              xml.tag! 'currency', options[:currency] || currency(money)              
              xml.tag! 'purchaseOrderNo', options[:order_id].to_s.gsub(/[ ']/, '')

              add_credit_card(xml, credit_card)
            end
          end
        end
        
        xml.target!
      end
      
      def build_request(action, body)
        
        xml = Builder::XmlMarkup.new
        xml.instruct!
        xml.tag! 'SecurePayMessage' do
          xml.tag! 'MessageInfo' do
            xml.tag! 'messageID', Utils.generate_unique_id.slice(0, 30)
            xml.tag! 'messageTimestamp', generate_timestamp
            xml.tag! 'timeoutValue', request_timeout
            xml.tag! 'apiVersion', action == :recurring ? "sp#{API_VERSION}" : API_VERSION
          end
          
          xml.tag! 'MerchantInfo' do
            xml.tag! 'merchantID', @options[:login]
            xml.tag! 'password', @options[:password]
          end
          xml << body
        end
        
        xml.target!
      end
      
      def add_credit_card(xml, credit_card)
        xml.tag! 'CreditCardInfo' do
          xml.tag! 'cardNumber', credit_card.number
          xml.tag! 'expiryDate', expdate(credit_card)
          xml.tag! 'cvv', credit_card.verification_value if credit_card.verification_value?
        end
      end

      def commit(action, request)
        response = parse(ssl_post(url_for(action), build_request(action, request)))
        require 'pp'
        pp build_request(action, request)
        
        Response.new(success?(response), message_from(response), response, 
          :test => test?, 
          :authorization => authorization_from(response)
        )
      end
      
      def url_for(action)
        url = test? ? TEST_URL : LIVE_URL
        path = (action == :recurring) ? '/periodic' : '/payment'
        
        url + path
      end
      
      def success?(response)
        SUCCESS_CODES.include?(response[:response_code])
      end
      
      def authorization_from(response)
        response[:txn_id]
      end
          
      def message_from(response)
        response[:response_text] || response[:status_description]
      end
      
      def expdate(credit_card)
        "#{format(credit_card.month, :two_digits)}/#{format(credit_card.year, :two_digits)}"
      end
      
      def parse(body)
        xml = REXML::Document.new(body)

        response = {}
        
        xml.root.elements.to_a.each do |node|
          parse_element(response, node)
        end

        response
      end

      def parse_element(response, node)
        if node.has_elements?
          node.elements.each{|element| parse_element(response, element) }
        else
          response[node.name.underscore.to_sym] = node.text
        end
      end
      
      # YYYYDDMMHHNNSSKKK000sOOO
      def generate_timestamp
        time = Time.now.utc
        time.strftime("%Y%d%m%H%M%S#{time.usec}+000")
      end  
    end
  end
end

