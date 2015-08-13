require 'nokogiri'
require 'digest/md5'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class GlobalOneGateway < Gateway
      self.test_url = 'https://testpayments.globalone.me/merchant/xmlpayment'
      self.live_url = 'https://payments.globalone.me/merchant/xmlpayment'

      self.supported_countries = ['CA', 'US']
      self.default_currency = 'CAD'
      self.supported_cardtypes = [:visa, :master, :american_express, :diners_club, :jcb]

      self.homepage_url = 'http://globalone.me/'
      self.display_name = 'GlobalOne'

      STANDARD_ERROR_CODE_MAPPING = {}

      def initialize(options={})
        requires!(options, :some_credential, :another_credential)
        # self.test_url = options[:test_url] if options[:test_url]
        # self.live_url = options[:live_url] if options[:live_url]
        super
      end

      def purchase(money, payment, options={})
        purdatetime = Time.now.strftime('%d-%m-%Y:%T:%L')
        ccexpmonth = payment.month < 10 ? "0#{payment.month}" : "#{payment.month}"
        ccexpyear = payment.expiry_date.year.to_s.length > 2 ? payment.expiry_date.year.to_s.slice(2,3) : payment.expiry_date.year.to_s
        ccexp = "#{ccexpmonth}#{ccexpyear}"
        purhash = Digest::MD5.hexdigest(options[:terminal_id]+options[:order_id]+money.to_s+purdatetime+options[:secret])
        request = build_xml_request do |xml|
          xml.PAYMENT do
            xml.ORDERID options[:order_id]
            xml.TERMINALID options[:terminal_id]
            xml.AMOUNT money
            xml.DATETIME purdatetime
            xml.CARDNUMBER payment.number
            xml.CARDTYPE payment.brand.upcase
            xml.CARDEXPIRY ccexp
            xml.CARDHOLDERNAME payment.name
            xml.HASH purhash
            xml.CURRENCY options[:currency]
            xml.TERMINALTYPE 2
            xml.TRANSACTIONTYPE 7
            xml.CVV payment.verification_value unless test?
          end
        end
        commit(request, 'PAYMENTRESPONSE')
      end

      def authorize(money, payment, options={})
        post = {}
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('authonly', post)
      end

      def capture(money, authorization, options={})
        commit('capture', post)
      end

      def refund(money, authorization, options={})
        purdatetime = Time.now.strftime('%d-%m-%Y:%T:%L')
        $stderr.puts(options.to_s + "<<<<<<<<<<<")
        $stderr.puts(authorization + "<<<<<<<<<<<")
        $stderr.puts(money.to_s + "<<<<<<<<<<<")
        $stderr.puts(purdatetime + "<<<<<<<<<<<")
        purhash = Digest::MD5.hexdigest(options[:terminal_id]+authorization.to_s+money.to_s+purdatetime+options[:secret])
        request = build_xml_request do |xml|
          xml.REFUND do
            xml.UNIQUEREF authorization
            xml.TERMINALID options[:terminal_id]
            xml.AMOUNT money
            xml.DATETIME purdatetime
            xml.HASH purhash
            xml.OPERATOR options[:operator]
            xml.REASON options[:reason]
          end
        end
        commit(request, 'REFUNDRESPONSE')
      end

      def void(authorization, options={})
        commit('void', post)
      end

      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript
      end

      private

      def build_xml_request
        builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
          yield(xml)
        end
        builder.to_xml
      end

      def add_customer_data(post, options)
      end

      def add_address(post, creditcard, options)
      end

      def add_invoice(post, money, options)
        post[:amount] = amount(money)
        post[:currency] = (options[:currency] || currency(money))
      end

      def add_payment(post, payment)
      end

      def parse(body)
        Hash.from_xml(body)
      end

      def commit(xml, response_type='PAYMENTRESPONSE')
        url = (test? ? test_url : live_url)

        headers = {
          'Content-Type' => 'application/xml;charset=UTF-8'
        }
        $stderr.puts "#{response_type} ========"
        response = parse(ssl_post(url, post_data(xml), headers))
        $stderr.puts "#{response} %%%%%%%%%%%%%%%%"
        logger.debug "#{response} %%%%%%%%%%%%%%%%"
        Response.new(
          success_from(response, response_type),
          message_from(response, response_type),
          response,
          authorization: authorization_from(response, response_type),
          test: test?,
          error_code: error_code_from(response, response_type)
        )
      end

      def success_from(response, response_type)
        true if response[response_type]['RESPONSECODE'] == 'A' rescue false
      end

      def message_from(response, response_type)
        response[response_type]['RESPONSETEXT'] rescue nil
      end

      def authorization_from(response, response_type)
         response[response_type]['APPROVALCODE'] rescue nil
      end

      def post_data(xml)
        "#{xml}"
      end

      def error_code_from(response, response_type)
        unless success_from(response, response_type)
          response['ERROR']['ERRORSTRING'] rescue nil
        end
      end
    end
  end
end
