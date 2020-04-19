require 'faraday'

module Payflow

  CARD_MAPPING = {
    :visa => 0,
    :master => 1,
    :discover => 2,
    :american_express => 3,
    :jcb => 5,
    :diners_club => 4
  }

  TRANSACTIONS = {
    :sale             => "S",
    :authorization    => "A",
    :capture          => "D",
    :void             => "V",
    :credit           => "C",
    :inquire          => "I",
    :generate_token   => "S",
    :checkout_details => "S",
    :checkout_payment => "S",
    :paypal_sale      => "S"
  }

  ACTIONS = {
    :checkout_details => 'G',
    :checkout_payment => 'D',
    :paypal_sale      => 'D'
  }

  DEFAULT_CURRENCY = "USD"

  SWIPED_ECR_HOST       = "MAGT"
  MAGTEK_CARD_TYPE      = 1
  REGISTERED_BY         = "PayPal"
  ENCRYPTION_BLOCK_TYPE = 1

  CREDIT_CARD_TENDER      = 'C'
  GENERATE_TOKEN_TENDER   = 'P'
  CHECKOUT_DETAILS_TENDER = 'P'
  CHECKOUT_PAYMENT_TENDER = 'P'
  PAYPAL_SALE_TENDER      = 'P'

  class Request
    attr_accessor :pairs, :options

    DEFAULT_TIMEOUT = 60

    TEST_HOST = 'pilot-payflowpro.paypal.com'
    LIVE_HOST = 'payflowpro.paypal.com'

    LIVE_PAYPAL_CHECKOUT_HOST = "https://www.paypal.com/checkoutnow"
    TEST_PAYPAL_CHECKOUT_HOST = "https://www.sandbox.paypal.com/checkoutnow"

    def initialize(action, money, payflow_credit_card = nil, _options = {})
      self.options = _options
      money = cast_amount(money)
      self.pairs   = initial_pairs(action, money, options[:pairs])

      case action
      when :sale, :authorization
        build_sale_or_authorization_request(action, money, payflow_credit_card, options)
      when :capture
        build_reference_request(action, money, payflow_credit_card, options)
      when :void
        build_reference_request(action, money, payflow_credit_card, options)
      when :inquire
        build_reference_request(action, money, payflow_credit_card, options)
      when :credit
        if payflow_credit_card.is_a?(String)
          build_reference_request(action, money, payflow_credit_card, options)
        else
          build_credit_card_request(action, money, payflow_credit_card, options)
        end
      when :generate_token
        build_generate_token_request(action, options)
      when :checkout_details
        build_checkout_details_request(action, options)
      when :checkout_payment
        build_checkout_payment_request(action, options)
      when :paypal_sale
        build_paypal_sale(action, payflow_credit_card, options)
      end
    end

    def build_sale_or_authorization_request(action, money, payflow_credit_card, options)
      if payflow_credit_card.is_a?(String)
        build_reference_request(action, money, payflow_credit_card, options)
      else
        build_credit_card_request(action, money, payflow_credit_card, options)
      end
    end

    def build_generate_token_request(action, options = {})
      pairs.tender = GENERATE_TOKEN_TENDER
      pairs.action = TRANSACTIONS[action]
      pairs.returnurl = test? ? "http://localhost:3000/error" : "#{ LIVE_PAYPAL_CHECKOUT_HOST }/error"
      pairs.cancelurl = test? ? "http://localhost:3000/cancel" : "#{ LIVE_PAYPAL_CHECKOUT_HOST }/cancel"
      pairs.orderdesc = options[:desc] || 'Payflow order transaction'
      pairs.invnum = options[:number] || "INX123"

      pairs
    end

    def build_checkout_details_request(action, options = {})
      pairs.tender = CHECKOUT_DETAILS_TENDER
      pairs.action = ACTIONS[action]
      pairs.token = options[:order_id]

      pairs
    end

    def build_paypal_sale(action, origid, options = {})
      pairs.action = ACTIONS[action]
      pairs.tender = PAYPAL_SALE_TENDER
      pairs.origid = origid
      pairs.capturecomplete = 'Y'
      pairs.currency = options[:currency] || DEFAULT_CURRENCY

      pairs
    end

    def build_checkout_payment_request(action, options = {})
      pairs.tender = CHECKOUT_PAYMENT_TENDER
      pairs.action = ACTIONS[action]
      pairs.token = options[:order_id]
      pairs.payerid = options[:payer_id]
      pairs.orderdesc = options[:desc] || 'Payflow order transaction'
      pairs.taxamt = options[:tax_amount] || 0
      pairs.itemamt = options[:total_item_amount] || 0
      pairs.freightamt = 0
      pairs.discount = options[:discount_amount] || 0
      pairs.currency = options[:currency] || DEFAULT_CURRENCY

      if options[:order_line_items].present?
        options[:order_line_items].each_with_index do |line_item, index|
          pairs["l_name#{ index }".to_sym] = line_item[:name]
          pairs["l_desc#{ index }".to_sym] = ""
          pairs["l_itemnumber#{ index }".to_sym] = line_item[:slug]
          pairs["l_cost#{ index }".to_sym] = line_item[:price]
          pairs["l_taxamt#{ index }".to_sym] = 0
          pairs["l_qty#{ index }".to_sym] = line_item[:quantity]
        end
      end

      pairs
    end

    def build_credit_card_request(action, money, credit_card, options)
      pairs.tender   = CREDIT_CARD_TENDER
      pairs.currency = options[:currency] || DEFAULT_CURRENCY

      add_credit_card!(credit_card)
    end

    def build_reference_request(action, money, authorization, options)
      pairs.tender = CREDIT_CARD_TENDER
      pairs.origid = authorization
    end

    def add_credit_card!(credit_card)
      pairs.card_type = credit_card_type(credit_card)
      if credit_card.encrypted?
        add_encrypted_credit_card!(credit_card)
      elsif credit_card.track2.present?
        add_swiped_credit_card!(credit_card)
      else
        add_keyed_credit_card!(credit_card)
      end
    end

    def credit_card_type(credit_card)
      return '' if credit_card.brand.blank?

      CARD_MAPPING[credit_card.brand.to_sym]
    end

    def expdate(creditcard)
      year  = sprintf("%.2i", creditcard.year.to_s.sub(/^0+/, '')).slice(-2, 2)
      month = sprintf("%.2i", creditcard.month.to_s.sub(/^0+/, ''))

      "#{month}#{year}"
    rescue ArgumentError
      ""
    end

    def commit(options = {})
      nvp_body = build_request_body

      return Payflow::MockResponse.new(nvp_body) if @options[:mock]

      response = connection.post do |request|
        add_common_headers!(request)
        request.headers["X-VPS-REQUEST-ID"] = options[:request_id] || SecureRandom.base64(20)
        request.body = nvp_body
      end

      Payflow::Response.new(response)
    end

    def test?
      @options[:test] == true
    end

    private
      def cast_amount(money)
        return nil if money.nil?
        money = money.to_f if money.is_a?(String)
        money = money.round(2) if money.is_a?(Float)
        "%.2f" % money
        #money.to_s # stored as a string to avoid float issues and Big Decimal formatting
      end

      def endpoint
        ENV['PAYFLOW_ENDPOINT'] || "https://#{test? ? TEST_HOST : LIVE_HOST}"
      end

      def connection
        @conn ||= Faraday.new(:url => endpoint) do |faraday|
          faraday.request  :url_encoded
          faraday.response :logger
          faraday.adapter  Faraday.default_adapter
        end
      end

      def add_common_headers!(request)
        request.headers["Content-Type"] = "text/name value"
        request.headers["X-VPS-CLIENT-TIMEOUT"] = (options[:timeout] || DEFAULT_TIMEOUT).to_s
        request.headers["X-VPS-VIT-Integration-Product"] = "Payflow Gem"
        request.headers["X-VPS-VIT-Runtime-Version"] = RUBY_VERSION
        request.headers["Host"] = test? ? TEST_HOST : LIVE_HOST
      end

      def initial_pairs(action, money, optional_pairs = {})
        struct = OpenStruct.new(
          trxtype: TRANSACTIONS[action]
        )
        if money and money.to_f > 0
          struct.amt = money
        end
        if optional_pairs
          optional_pairs.each do |key, value|
            struct.send("#{key}=", value)
          end
        end
        struct
      end

      def add_swiped_credit_card!(credit_card)
        pairs.swipe = credit_card.track2
        pairs
      end

      def add_keyed_credit_card!(credit_card)
        pairs.acct    = credit_card.number
        pairs.expdate = expdate(credit_card)
        pairs.cvv2    = credit_card.security_code if credit_card.security_code.present?

        pairs
      end

      def add_encrypted_credit_card!(credit_card)
        pairs.swiped_ecr_host       = SWIPED_ECR_HOST
        pairs.enctrack2             = credit_card.track2
        pairs.encmp                 = credit_card.mp
        pairs.devicesn              = credit_card.device_sn
        pairs.mpstatus              = credit_card.mpstatus
        pairs.encryption_block_type = ENCRYPTION_BLOCK_TYPE
        pairs.registered_by         = REGISTERED_BY
        pairs.ksn                   = credit_card.ksn
        pairs.magtek_card_type      = MAGTEK_CARD_TYPE
      end

      def add_authorization!
        pairs.vendor   = @options[:login]
        pairs.partner  = @options[:partner]
        pairs.pwd      = @options[:password]
        pairs.user     = @options[:user].blank? ? @options[:login] : @options[:user]
      end

      def build_request_body
        add_authorization!

        pairs.marshal_dump.map{|key, value|
          "#{key.to_s.upcase.gsub("_", "")}[#{value.to_s.length}]=#{value}"
        }.join("&")
      end
  end
end
