module Habitations
  class ExternalIntake
    class Invalid < StandardError; end
    class Conflict < StandardError; end

    COUNTS = { "quartos" => :dormitorios_qtd, "suites" => :suites_qtd,
               "banheiros" => :banheiros_qtd, "vagas" => :vagas_qtd, "demi_suites" => :demi_suites_qtd }.freeze
    PRICES = { "valor_venda_centavos" => :valor_venda_cents, "valor_locacao_centavos" => :valor_locacao_cents,
               "valor_condominio_centavos" => :valor_condominio_cents, "valor_iptu_anual_centavos" => :valor_iptu_cents }.freeze

    def initialize(tenant, payload)
      @tenant = tenant
      @payload = payload
      @receipts = PropertyIntakeReceipt.for_tenant(tenant)
    end

    def call
      raise Invalid, "Envie um objeto JSON" unless @payload.is_a?(Hash)

      external_id = string(@payload, "external_id")
      @digest = Digest::SHA256.hexdigest(JSON.generate(canonical(@payload)))
      existing = @receipts.find_by(external_id: external_id)
      return replay(existing) if existing

      habitation, receipt_attributes, photo_urls = build_records
      document_specs = documents
      photos = []
      document_files = []
      @blobs = []
      photo_urls.each { |url| photos << ExternalIntakePhoto.download(url) }
      document_specs.each { |doc| document_files << ExternalIntakePhoto.download(doc.fetch("url"), document: true) }

      @tenant.with_lock(requires_new: true) do
        existing = @receipts.find_by(external_id: external_id)
        next replay(existing) if existing

        habitation.save!
        attach_photos(habitation, photos)
        document_files.zip(document_specs).each do |file, spec|
          attachment = spec.fetch("tipo") == "autorizacao" ? :autorizacoes_venda : :documentos
          attach_files(habitation, [file], attachment)
        end
        HabitationIntakeSplitter.new(habitation).call!
        receipt = @receipts.create!(receipt_attributes.merge(
          habitation: habitation, external_id: external_id, payload_digest: @digest
        ))
        [receipt, true]
      end
    rescue StandardError
      @blobs&.each { |blob| blob.delete unless ActiveStorage::Blob.exists?(blob.id) }
      raise
    ensure
      photos&.each { |photo| photo.tempfile.close! }
      document_files&.each { |file| file.tempfile.close! }
    end

    private

    def replay(receipt)
      raise Conflict unless receipt.payload_digest == @digest

      [receipt, false]
    end

    def canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    def build_records
      property = object(@payload, "imovel")
      captador = object(@payload, "captador")
      owner = object(@payload, "proprietario")
      address = object(property, "endereco")
      category = Habitation::CATEGORIES.find { |name| name.parameterize == string(property, "categoria").tr("_", "-").parameterize }
      raise Invalid, "categoria inválida" unless category

      modality = string(property, "modalidade")
      raise Invalid, "modalidade inválida" unless modality.in?(%w[venda locacao])

      sale = modality == "venda"
      phone = string(owner, "telefone", required: false)
      email = string(owner, "email", required: false)
      raise Invalid, "Informe telefone ou e-mail do proprietário" if phone.blank? && email.blank?

      habitation = @tenant.habitations.new(
        categoria: category, status: sale ? "Venda" : "Aluguel",
        intake_modalidade: sale ? "venda" : "locacao_anual",
        intake_origin: Habitation::INTAKE_ORIGIN_BROKER, intake_status: "draft",
        exibir_no_site_flag: false, titulo_anuncio: string(property, "titulo", required: false),
        descricao_web: string(property, "descricao", required: false, limit: 10_000),
        proprietario: string(owner, "nome"), proprietario_celular: phone, proprietario_email: email
      )
      habitation.build_address(address_attributes(address))
      apply_optional_fields(habitation, property)
      assign_captador(habitation, captador)
      COUNTS.each { |key, attribute| habitation[attribute] = integer(property, key, max: 2_147_483_647) if property.key?(key) }
      PRICES.each { |key, attribute| habitation[attribute] = integer(property, key) if property.key?(key) }
      raise Invalid, "Informe o valor da negociação" unless habitation[sale ? :valor_venda_cents : :valor_locacao_cents].to_i.positive?

      %w[area_privativa_m2 area_total_m2].each do |key|
        next unless property.key?(key)

        area = property[key]
        raise Invalid, "#{key} inválida" unless area.is_a?(Numeric) && area.finite? && area.between?(0, 99_999_999.99)

        habitation[key] = area
      end

      attributes = {
        captador_external_id: string(captador, "external_id"),
        captador_nome: string(captador, "nome"),
        captured_at: captured_at
      }
      [habitation, attributes, photo_urls(property)]
    end

    def address_attributes(address)
      %w[cep logradouro numero complemento bairro cidade uf].index_with do |key|
        string(address, key, required: key != "complemento")
      end
    end

    def captured_at
      Time.iso8601(string(@payload, "captured_at"))
    rescue ArgumentError
      raise Invalid, "captured_at deve estar em ISO 8601"
    end

    def photo_urls(property)
      photos = property.fetch("fotos", [])
      unless photos.is_a?(Array) && photos.size <= 10 && photos.all?(Hash)
        raise Invalid, "Envie até 10 fotos"
      end

      ordered = photos.map { |photo| [integer(photo, "ordem", min: 1), string(photo, "url", limit: 4096)] }
      raise Invalid, "A ordem das fotos deve ser única" if ordered.map(&:first).uniq.size != ordered.size

      ordered.sort.map(&:last)
    end

    def attach_photos(habitation, photos)
      return if photos.empty?

      attach_files(habitation, photos, :photos)
      habitation.reload
      habitation.update!(photo_ids_order: habitation.photos.attachments.order(:id).ids)
    end

    def attach_files(habitation, files, attachment)
      service = Storage::Routing.service_name_for(record: habitation, name: attachment)
      Storage::ActiveStorageRegistry.fetch!(service) unless service.to_sym == :local
      blobs = files.each_with_index.map do |file, index|
        blob = ActiveStorage::Blob.create_after_unfurling!(
          io: file, filename: file.original_filename, content_type: file.content_type,
          identify: false, service_name: service,
          metadata: { tenant_id: @tenant.id, source: "external_intake", position: index + 1 }
        )
        @blobs << blob
        file.rewind
        blob.upload_without_unfurling(file)
        blob
      end
      habitation.public_send(attachment).attach(blobs)
      habitation.save!
    end

    def documents
      items = @payload.fetch("documentos", [])
      unless items.is_a?(Array) && items.size <= 10 && items.all?(Hash)
        raise Invalid, "Envie até 10 documentos"
      end

      items.map do |item|
        type = string(item, "tipo")
        raise Invalid, "tipo de documento inválido" unless type.in?(%w[autorizacao documento])

        { "tipo" => type, "url" => string(item, "url", limit: 4096) }
      end
    end

    def assign_captador(habitation, captador)
      email = string(captador, "email", required: false)
      return if email.blank?

      user = @tenant.admin_users.active.where("LOWER(email) = ?", email.strip.downcase).sole
      habitation.broker_assignments.build(admin_user: user, role: :captador)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::SoleRecordExceeded
      raise Invalid, "captador.email deve identificar um usuário ativo desta conta"
    end

    def apply_optional_fields(habitation, property)
      {
        "torre" => :bloco, "nome_condominio" => :nome_empreendimento,
        "tipo_vaga" => :tipo_vaga, "box" => :numero_box,
        "onde_estao_as_chaves" => :key_location,
        "observacoes_chaves" => :key_location_notes,
        "observacoes_internas" => :descricao_interna,
        "observacoes_restritas" => :observacoes,
        "tipo_cadastro" => :tipo
      }.each do |key, attribute|
        habitation[attribute] = string(property, key, required: false, limit: attribute.in?([:observacoes, :descricao_interna]) ? 10_000 : 255) if property.key?(key)
      end
      if property.key?("tipo_cadastro") && !habitation.tipo.in?(["Unitário", "Empreendimento"])
        raise Invalid, "tipo_cadastro inválido"
      end
      { "permuta" => :aceita_permuta_flag, "parcelamento" => :aceita_parcelamento_flag,
        "administracao_locacao" => :rental_management_flag }.each do |key, attribute|
        next unless property.key?(key)
        raise Invalid, "#{key} deve ser booleano" unless property[key] == true || property[key] == false

        habitation[attribute] = property[key]
      end
      if property.key?("administracao_locacao")
        habitation.rental_management_answer = property["administracao_locacao"] ? "sim" : "nao"
      end
    end

    def object(parent, key)
      value = parent[key]
      raise Invalid, "#{key} deve ser um objeto" unless value.is_a?(Hash)

      value
    end

    def string(parent, key, required: true, limit: 255)
      value = parent[key]
      return if value.nil? && !required
      unless value.is_a?(String) && value.bytesize <= limit && (!required || value.present?) && !value.include?("\0")
        raise Invalid, "#{key} inválido"
      end

      value
    end

    def integer(parent, key, min: 0, max: 9_223_372_036_854_775_807)
      value = parent[key]
      raise Invalid, "#{key} inválido" unless value.is_a?(Integer) && value.between?(min, max)

      value
    end
  end
end
