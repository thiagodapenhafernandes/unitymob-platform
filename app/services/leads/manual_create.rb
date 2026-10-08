module Leads
  class ManualCreate
    attr_reader :duplicate

    def initialize(lead)
      @lead = lead
    end

    def call
      # ponytail: serializa cadastros manuais da conta; lock por contato se houver contenção.
      @lead.tenant.with_lock do
        matches = ContactMatch.apply(@lead.tenant.leads, @lead, "phone_or_email")
        @duplicate = matches&.order(:id)&.first
        if duplicate
          @lead.errors.add(:base, "O telefone ou e-mail informado já está cadastrado nesta conta. Utilize o lead existente ou solicite acesso ao responsável.")
          false
        else
          @lead.save
        end
      end
    end
  end
end
