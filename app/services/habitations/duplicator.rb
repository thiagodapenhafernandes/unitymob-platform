# frozen_string_literal: true

module Habitations
  class Duplicator
    Result = Struct.new(:habitation, keyword_init: true)

    DUPLICABLE_ATTRIBUTE_NAMES = %w[
      categoria status situacao tipo codigo_empreendimento nome_empreendimento
      tipo_endereco endereco numero complemento bairro cidade uf cep pais latitude longitude
      dormitorios_qtd suites_qtd banheiros_qtd vagas_qtd elevadores_qtd salas_qtd varandas_qtd
      area_privativa_m2 area_total_m2 area_terreno_m2 area_util_m2
      valor_venda_cents valor_locacao_cents valor_condominio_cents valor_iptu_cents valor_por_m2_cents
      valor_promocional_cents valor_total_aluguel_cents valor_comissao_cents valor_livre_proprietario_cents
      caracteristicas infra_estrutura destaque_localizacao caracteristica_unica
      pictures videos plantas fotos_empreendimento
      descricao_web descricao_interna titulo_anuncio observacoes
      corretor_nome corretor_telefone corretor_email admin_user_id constructor_id
      lancamento_flag aceita_permuta_flag aceita_financiamento_flag mobiliado_flag piscina_flag lavabo_flag
      varanda_gourmet_flag banheiro_social_qtd decorado_flag garden_flag quadra_mar_flag sem_mobilia_flag
      tem_placa_flag exclusivo_flag home_corporate_flag home_corporate_position
      bairro_comercial bloco lote imediacoes quadra
      aptos_andar aptos_edificio construtora inscricao_imobiliaria descricao_empreendimento
      terceira_avenida_flag arriba_flag avenida_brasil_flag bairro_fazenda_itajai_flag
      balneario_picarras_flag barra_flag barra_norte_flag barra_sul_flag cabecudas_flag camboriu_flag
      centro_flag estaleirinho_flag frente_mar_avenida_atlantica_flag itajai_flag itapema_flag nacoes_flag
      pioneiros_flag praia_brava_flag praia_dos_amores_flag vista_frente_mar_flag festival_salute_flag
      categoria_grupo data_entrega tour_virtual face perfil_construcao tipo_vaga hidromassagem_qtd
      ocupacao_status estado_conservacao andar ano_construcao demi_suites_qtd numero_box
      dimensoes_terreno topografia foto_classificacao podcast_url
      captador_commission_percentage broker_commission_percentage salute_rental_management_flag
      valor_aceito_permuta_cents aceita_permuta_veiculo_flag aceita_permuta_imovel_flag aceita_permuta_outros_flag
      tipo_veiculo_aceito_permuta ano_minimo_veiculo_aceito_permuta permuta_valor_cents
      permuta_localizacao permuta_dormitorios_qtd permuta_suites_qtd permuta_garagens_qtd
      matricula_imovel zona aceita_doacao_flag condicoes_negociacao saldo_devedor_cents numero_prestacoes
      responsavel_reserva zelador_nome zelador_telefone observacoes_visitas regiao_foco tipo_fachada andares_qtd
      destaque_chaves_na_mao periodo_locacao_chaves_na_mao modelo_casa_mineira tipo_publicacao_viva_real
      divulgar_endereco_viva_real tipo_publicacao_imovelweb mostrar_mapa_imovelweb tipo_publicacao_imovelweb_2
      mostrar_mapa_imovelweb_2 aceita_parcelamento_flag salute_rental_management_answer aceita_permuta_answer
      motivo_venda intake_modalidade use_development_photos_flag motivo_suspensao valor_alugado_terceiros_cents
      valor_vendido_terceiros_cents rental_guarantee_method permuta_valor_percentual frente_terreno_m fundo_terreno_m
      permuta_veiculo_valor_cents permuta_outros_valor_cents permuta_outros_descricao
      public_map_display_mode public_street_view_mode public_rating_value public_rating_count public_rating_source
      meta_title meta_description meta_keywords
    ].freeze

    SENSITIVE_ATTRIBUTE_NAMES = %w[
      proprietario_codigo proprietario proprietario_email proprietario_celular
      proprietario_telefone_comercial proprietario_telefone_residencial proprietor_id
      key_location key_location_notes
    ].freeze

    BROKER_ASSIGNMENT_ATTRIBUTE_NAMES = %w[
      admin_user_id commission_value observations
      sale_commission_percentage rental_commission_percentage rental_cancellation_commission_percentage
      sale_commission_cents rental_commission_cents rental_cancellation_commission_cents
    ].freeze

    attr_reader :source, :actor, :tenant, :request, :copy_sensitive_data, :copy_internal_documents

    def initialize(source, actor:, tenant:, request: nil, copy_sensitive_data: false, copy_internal_documents: false)
      @source = source
      @actor = actor
      @tenant = tenant
      @request = request
      @copy_sensitive_data = copy_sensitive_data
      @copy_internal_documents = copy_internal_documents
    end

    def call!
      raise ActiveRecord::RecordNotFound unless source&.tenant_id == tenant&.id

      duplicate = nil

      Habitation.transaction do
        duplicate = tenant.habitations.new(duplicable_attributes)
        prepare_duplicate!(duplicate)
        duplicate.save!

        copy_address_to(duplicate)
        photo_id_map = copy_attachment_collection(source.photos, duplicate, :photos)
        copy_internal_attachments_to(duplicate) if copy_internal_documents
        copy_broker_assignments_to(duplicate)
        copy_rich_text_to(duplicate)
        preserve_photo_order!(duplicate, photo_id_map)
        record_duplicate_created!(duplicate)
      end

      Result.new(habitation: duplicate)
    end

    private

    def duplicable_attributes
      names = DUPLICABLE_ATTRIBUTE_NAMES & Habitation.column_names
      names += SENSITIVE_ATTRIBUTE_NAMES if copy_sensitive_data

      source.attributes.slice(*names)
    end

    def prepare_duplicate!(duplicate)
      duplicate.codigo = nil
      duplicate.slug = nil
      duplicate.skip_auto_audit = true
      duplicate.tenant = tenant
      duplicate.data_cadastro_crm = Time.current
      duplicate.data_atualizacao_crm = Time.current
      duplicate.preco_atualizado_em = nil if duplicate.has_attribute?(:preco_atualizado_em)
      duplicate.valor_venda_anterior_cents = nil if duplicate.has_attribute?(:valor_venda_anterior_cents)
      duplicate.valor_locacao_anterior_cents = nil if duplicate.has_attribute?(:valor_locacao_anterior_cents)
      duplicate.intake_origin = nil
      duplicate.intake_status = "internal" if duplicate.has_attribute?(:intake_status)
      duplicate.intake_step = "intro" if duplicate.has_attribute?(:intake_step)
      duplicate.intake_group_uuid = nil if duplicate.has_attribute?(:intake_group_uuid)
      duplicate.submitted_for_review_at = nil
      duplicate.admin_reviewed_by = nil
      duplicate.admin_reviewed_at = nil
      duplicate.admin_review_notes = nil
      duplicate.admin_review_return_reason = nil if duplicate.has_attribute?(:admin_review_return_reason)
      duplicate.broker_released_at = nil
      reset_publication_state!(duplicate)
      reset_integration_identity!(duplicate)
      reset_photo_publication_state!(duplicate)
    end

    def reset_publication_state!(duplicate)
      portal_columns = Habitation::PORTAL_PUBLICATION_FIELDS.values.map(&:to_s)
      dynamic_columns = Habitation.column_names.grep(/\Apublicar_/)
      site_columns = Habitation::SITE_PUBLICATION_FIELDS.map(&:to_s)
      publication_columns = (site_columns + portal_columns + dynamic_columns).uniq & duplicate.attribute_names
      publication_columns.each { |name| duplicate[name] = false }
      duplicate.destaque_web_flag = false if duplicate.has_attribute?(:destaque_web_flag)
      duplicate.home_corporate_flag = false if duplicate.has_attribute?(:home_corporate_flag)
      duplicate.home_corporate_position = nil if duplicate.has_attribute?(:home_corporate_position)
    end

    def reset_integration_identity!(duplicate)
      %w[
        codigo_dwv imovel_dwv codigo_corretor captador_account_id agenciador
        status_vista last_sync_at last_sync_status last_sync_message vista_import_batch_id
        vista_codigo vista_imo_codigo vista_imo_placa vista_referencia_externa
      ].each do |name|
        duplicate[name] = nil if duplicate.has_attribute?(name)
      end

      duplicate.vista_payload = {} if duplicate.has_attribute?(:vista_payload)
      duplicate.dwv_payload = {} if duplicate.has_attribute?(:dwv_payload)
    end

    def reset_photo_publication_state!(duplicate)
      duplicate.photo_ids_order = [] if duplicate.has_attribute?(:photo_ids_order)
      duplicate.site_hidden_photo_ids = [] if duplicate.has_attribute?(:site_hidden_photo_ids)
      duplicate.photo_environment_assignments = {} if duplicate.has_attribute?(:photo_environment_assignments)
      %w[photo_calendar_provider photo_calendar_event_id photo_calendar_error photo_calendar_synced_at].each do |name|
        duplicate[name] = nil if duplicate.has_attribute?(name)
      end
    end

    def copy_address_to(target)
      return unless source.address

      attrs = source.address.attributes.except("id", "addressable_id", "addressable_type", "created_at", "updated_at")
      target.create_address!(attrs)
    end

    def copy_internal_attachments_to(target)
      copy_attachment_collection(source.fichas_cadastro, target, :fichas_cadastro)
      copy_attachment_collection(source.autorizacoes_venda, target, :autorizacoes_venda)
    end

    def copy_attachment_collection(source_attachments, target, association_name)
      source_attachments.attachments.includes(:blob).each_with_object({}) do |attachment, mapping|
        target_attachment = ActiveStorage::Attachment.create!(
          name: association_name.to_s,
          record: target,
          blob: attachment.blob
        )
        mapping[attachment.id] = target_attachment.id if target_attachment
      end
    end

    def preserve_photo_order!(target, photo_id_map)
      ordered_source_ids = Array(source.photo_ids_order).map(&:to_i)
      return if ordered_source_ids.blank? || photo_id_map.blank?

      ordered_target_ids = ordered_source_ids.filter_map { |id| photo_id_map[id] }
      return if ordered_target_ids.blank?

      target.update_columns(photo_ids_order: ordered_target_ids, updated_at: Time.current)
    end

    def copy_broker_assignments_to(target)
      source.broker_assignments.find_each do |assignment|
        attrs = assignment.attributes.slice(*BROKER_ASSIGNMENT_ATTRIBUTE_NAMES)
        attrs["role"] = assignment.role
        attrs["commission_type"] = assignment.commission_type
        target.broker_assignments.create!(attrs)
      end
    end

    def copy_rich_text_to(target)
      target.update!(descricao_web: source.descricao_web.body.to_html) if source.descricao_web.body.present?
      target.update!(meta_description: source.meta_description.body.to_html) if source.meta_description.body.present?
    end

    def record_duplicate_created!(duplicate)
      Habitations::AuditChangeRecorder.new(
        duplicate,
        actor: actor,
        request: request,
        source: "admin",
        metadata: {
          duplicated_from_habitation_id: source.id,
          duplicated_from_codigo: source.codigo
        }
      ).record_create!
    end
  end
end
