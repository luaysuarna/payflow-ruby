module Payflow
  class Response
    attr_accessor :result, :http_response

    def initialize(http_response)
      @http_response = http_response
      @result = parse(http_response)
    end

    def successful?
      result[:result] == "0"
    end
    alias :success? :successful?

    def message
      result[:respmsg]
    end

    def authorization_token
      result[:pnref] || @result[:rpref]
    end

    alias :token :authorization_token

    def avs_result
      result[:avsresult]
    end

    def cvv_result
      result[:cvresult]
    end

    private

      def parse(http_response)
        pairs = http_response.body.split("&")
        response = {}

        pairs.each do |node|
          parse_element(response, node)
        end

        response
      end

      def parse_element(response, pair)
        response[pair.split("=").first.underscore.to_sym] = pair.split("=").last
      end
  end
end