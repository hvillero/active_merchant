require 'nokogiri'
require 'digest/md5'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class GlobalOneGateway < Gateway
      self.test_url = 'https://testpayments.globalone.me/merchant/xmlpayment'
      # self.live_url = 'https://example.com/live'

      self.supported_countries = ['CA', 'US']
      self.default_currency = 'CAD'
      self.supported_cardtypes = [:visa, :master, :american_express, :diners_club, :jcb]

      self.homepage_url = 'http://globalone.me/'
      self.display_name = 'GlobalOne'

      STANDARD_ERROR_CODE_MAPPING = {}

      def initialize(options={})
        requires!(options, :some_credential, :another_credential)
        super
      end

      def purchase(money, payment, options={})
        purdatetime = Time.now.strftime('%d-%m-%Y:%T:%L')
        purhash = Digest::MD5.hexdigest('33002'+options[:order_id]+'CAD'+money.to_s+purdatetime+'secret')
        # $stderr.puts purhash
        request = build_xml_request do |xml|
          xml.PAYMENT do
            xml.ORDERID options[:order_id]
            xml.TERMINALID '33002'
            xml.AMOUNT money
            xml.DATETIME purdatetime
            xml.CARDNUMBER payment.number
            xml.CARDTYPE payment.brand.upcase
            xml.CARDEXPIRY '0816'
            xml.CARDHOLDERNAME payment.name
            xml.HASH purhash
            xml.CURRENCY 'CDN'
            xml.TERMINALTYPE 2
            xml.TRANSACTIONTYPE 7
            xml.CVV payment.verification_value
          end
        end
        commit(request)
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
        commit('refund', post)
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
        {}
      end

      def commit(xml)
        # url = (test? ? test_url : live_url)
        # response = parse(ssl_post(url, post_data(action, parameters)))

        # Response.new(
        #   success_from(response),
        #   message_from(response),
        #   response,
        #   authorization: authorization_from(response),
        #   avs_result: AVSResult.new(code: response["some_avs_response_key"]),
        #   cvv_result: CVVResult.new(response["some_cvv_response_key"]),
        #   test: test?,
        #   error_code: error_code_from(response)
        # )
        url = (test? ? test_url : live_url)
        headers = {
          'Content-Type' => 'application/x-www-form-urlencoded;charset=UTF-8'
        }

        response = parse(ssl_post(url, post_data(xml), headers))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          test: test?
        )
      end

      def success_from(response)
      end

      def message_from(response)
      end

      def authorization_from(response)
      end

      def post_data(xml)
        "load=#{xml}"
      end

      def error_code_from(response)
        unless success_from(response)
          # TODO: lookup error code for this response
        end
      end
    end
  end
end
