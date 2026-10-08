module Leads
  # Complemento de consultas: nova consulta da mesma pessoa (qualquer origem)
  # não vira lead novo quando ela já tem lead aberto com corretor dentro do
  # tempo de atendimento (pocket da regra que distribuiu). Em vez disso, o
  # imóvel consultado entra como interesse do lead existente, com atividade
  # na timeline e aviso ao dono. Uma pessoa nunca fica com dois corretores.
  class InquiryComplement
    MAX_PREVIOUS_LEADS = 25

    def self.keeps_owner?(target, inquiry)
      new(inquiry).keeps_owner?(target)
    end

    def self.target_for(lead)
      new(lead).target
    end

    def self.complement!(target, inquiry, notify: true, metadata: {})
      new(inquiry).complement!(target, notify: notify, metadata: metadata)
    end

    # Caminho completo usado na distribuição: detecta o alvo, agrega a
    # consulta e descarta o registro transitório em transação. Retorna o
    # alvo ou nil (sem alvo ou falha — quem chama segue o fluxo normal).
    def self.dissolve_into_target!(lead)
      target = target_for(lead)
      return nil if target.nil?

      Lead.transaction do
        new(lead).complement!(target)
        lead.complemented_into_id = target.id
        lead.destroy!
      end
      Rails.logger.info("[InquiryComplement] Lead #{lead.id} agregada ao lead #{target.id} (tenant_id=#{lead.tenant_id}).")
      target
    rescue => e
      Rails.logger.error("[InquiryComplement] complemento falhou pro lead #{lead.id}: #{e.class}: #{e.message}")
      lead.complemented_into_id = nil
      nil
    end

    def initialize(lead)
      @lead = lead
    end

    def target
      return nil if @lead.admin_user_id.present?
      return nil if @lead.tenant.nil?

      scope = Intake.matches(@lead)
      return nil if scope.nil?

      scope = scope
        .where.not(admin_user_id: nil)
        .where(archived_at: nil)
        .where.not(status: Lead.non_operational_status_values(tenant: @lead.tenant))

      candidates = scope.reorder(created_at: :desc, id: :desc).limit(MAX_PREVIOUS_LEADS).to_a
      users_by_id = @lead.tenant.admin_users.where(id: candidates.map(&:admin_user_id)).index_by(&:id)
      candidates.find do |candidate|
        users_by_id[candidate.admin_user_id]&.active? && keeps_owner?(candidate)
      end
    end

    def keeps_owner?(candidate)
      candidate.archived_at.blank? &&
        !Lead.non_operational_status_values(tenant: candidate.tenant).include?(candidate.status) &&
        !setting.non_fidelizing_stage_for_stickiness?(candidate.lead_pipeline_stage_id) && within_pocket?(candidate)
    end

    def complement!(target, notify: true, metadata: {})
      habitation = @lead.property_id.present? ? target.tenant.habitations.find_by(id: @lead.property_id) : nil
      target.property_interests.find_or_create_by!(habitation: habitation) { |interest| interest.tenant = target.tenant } if habitation
      fill_contact_blanks(target)
      merge_information(target)
      target.save! if target.changed?

      LeadActivity.log!(lead: target, kind: "inquiry_complemented", metadata: complement_metadata(target, habitation).merge(metadata))
      NotificationDispatcher.notify_complement(target, habitation) if notify
      target
    end

    private

    def setting
      @setting ||= LeadSetting.instance(tenant: @lead.tenant)
    end

    def within_pocket?(candidate)
      rule = candidate.distribution_rule
      return false unless rule&.pocket_active? && rule.pocket_time.to_i.positive?

      distributed_at = candidate.activities.where(kind: "distributed").order(created_at: :desc).pick(:created_at) || candidate.created_at
      distributed_at >= rule.pocket_time.to_i.minutes.ago
    end

    def fill_contact_blanks(target)
      %i[name email phone client_name client_email client_phone].each do |field|
        target[field] = @lead[field] if target[field].blank? && @lead[field].present?
      end
    end

    def merge_information(target)
      merged = @lead.other_information.to_h.merge(target.other_information.to_h)
      target.other_information = merged if merged != target.other_information.to_h
    end

    def complement_metadata(target, habitation)
      attribution = @lead.attribution_data.to_h
      {
        ingress_reference: Intake.event_reference(@lead),
        inquiry_information: @lead.other_information.to_h,
        inquiry_answers: @lead.custom_answers,
        inquiry_contact: @lead.attributes.slice("name", "phone", "email", "client_name", "client_phone", "client_email"),
        inquiry_attribution: @lead.attribution_data.to_h,
        body: @lead.notes.presence,
        inquiry_origin: @lead.origin,
        inquiry_lead_type: @lead.lead_type,
        property_id: habitation&.id,
        property_code: habitation&.codigo,
        property_title: habitation&.display_title,
        source_url: @lead.source_url,
        channel: attribution["channel"] || @lead.attribution_channel,
        source: attribution["source"] || @lead.attribution_source,
        inquiry_at: Time.current.iso8601
      }.compact
    end
  end
end
