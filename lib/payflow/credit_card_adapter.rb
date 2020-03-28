module Payflow
  class CreditCardAdapter
    attr_accessor :credit_card

    def initialize(credit_card)
      self.credit_card = credit_card
    end

    def call
      return credit_card if credit_card.is_a?(Payflow::CreditCard) || credit_card.is_a?(String)
      return credit_card[:reference_id] if credit_card[:reference_id].present? # just a string

      if payflow_encrypted? and !magensa_encrypted?
        @payflow_card ||= encrypted_payflow_card
      else
        @payflow_card ||= unencrypted_payflow_card
      end

      @payflow_card
    end

    def encrypted_payflow_card
      Payflow::CreditCard.new(
        base_hash.merge(
          ksn: credit_card[:ksn],
          mpstatus: credit_card[:mpstatus],
          device_sn: credit_card[:device_sn],
          track2: credit_card[:track2],
          mp: credit_card[:mp]
        )
      )
    end

    def unencrypted_payflow_card
      Payflow::CreditCard.new(
        base_hash.merge(
          number: credit_card[:number],
          track2: credit_card[:plaintrack2]
        )
      )
    end

    def base_hash
      {
        year: credit_card[:year],
        first_name: credit_card[:first_name],
        last_name: credit_card[:last_name],
        month: credit_card[:month]
      }
    end

    def payflow_encrypted?
      credit_card[:encrypted] && credit_card[:mp] && credit_card[:mp].strip =~ /0{112}/
    end

    def magensa_encrypted?
      credit_card[:encrypted] && credit_card[:mp].present?
    end

    def self.run(credit_card)
      self.new(credit_card).call
    end
  end
end
