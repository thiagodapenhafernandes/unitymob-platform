class HabitationIntakeSplitter
  SPLIT_RENT_MODALITY = "locacao_anual".freeze

  def initialize(habitation, submitted_at: Time.current, target_intake_status: "submitted_for_admin_review")
    @habitation = habitation
    @submitted_at = submitted_at
    @target_intake_status = target_intake_status
  end

  def call!
    return submit_single! unless @habitation.modalidade == "ambos"

    split!
  end

  private

  def submit_single!
    @habitation.finalize_broker_intake_registration!(submitted_at: @submitted_at)
    @habitation.update!(
      intake_status: @target_intake_status,
      submitted_for_review_at: @submitted_at,
      intake_step: "review"
    )
    [@habitation]
  end

  def split!
    group_uuid = @habitation.intake_group_uuid.presence || SecureRandom.uuid
    sale_price_cents = @habitation.valor_venda_cents
    rent_price_cents = @habitation.valor_locacao_cents
    rental = nil

    Habitation.transaction do
      @habitation.finalize_broker_intake_registration!(submitted_at: @submitted_at)
      @habitation.update!(
        intake_group_uuid: group_uuid,
        intake_modalidade: "venda",
        status: "Venda",
        valor_venda_cents: sale_price_cents,
        valor_locacao_cents: 0,
        intake_status: @target_intake_status,
        submitted_for_review_at: @submitted_at,
        intake_step: "review"
      )

      rental = build_rental_copy(group_uuid, rent_price_cents)
      rental.save!
      copy_address_to(rental)
      copy_attachments_to(rental)
      copy_rich_text_to(rental)
    end

    [@habitation, rental]
  end

  def build_rental_copy(group_uuid, rent_price_cents)
    @habitation.dup.tap do |copy|
      copy.codigo = nil
      copy.slug = nil
      copy.status = "Aluguel"
      copy.intake_modalidade = SPLIT_RENT_MODALITY
      copy.intake_group_uuid = group_uuid
      copy.valor_venda_cents = 0
      copy.valor_locacao_cents = rent_price_cents
      copy.intake_status = @target_intake_status
      copy.submitted_for_review_at = @submitted_at
      copy.intake_step = "review"
      copy.exibir_no_site_flag = false
      copy.finalize_broker_intake_registration!(submitted_at: @submitted_at)
    end
  end

  def copy_address_to(target)
    return unless @habitation.address

    attrs = @habitation.address.attributes.except("id", "addressable_id", "addressable_type", "created_at", "updated_at")
    target.create_address!(attrs)
  end

  def copy_attachments_to(target)
    copy_attachment_collection(@habitation.photos, target.photos)
    copy_attachment_collection(@habitation.fichas_cadastro, target.fichas_cadastro)
    copy_attachment_collection(@habitation.autorizacoes_venda, target.autorizacoes_venda)
  end

  def copy_attachment_collection(source, target)
    source.attachments.each { |attachment| target.attach(attachment.blob) }
  end

  def copy_rich_text_to(target)
    target.update!(descricao_web: @habitation.descricao_web.body.to_html) if @habitation.descricao_web.body.present?
    target.update!(meta_description: @habitation.meta_description.body.to_html) if @habitation.meta_description.body.present?
  end
end
