require "bigdecimal"

module Dwv
  class PropertyImportService
    DEFAULT_CATEGORY = "Apartamento".freeze

    def self.extract_collection(payload)
      case payload
      when Array
        payload
      when Hash
        payload["data"] || payload[:data] || payload["properties"] || payload[:properties] || payload["items"] || payload[:items] || []
      else
        []
      end
    end

    def self.extract_property_id(payload)
      value(payload, ["id"], ["propertyId"], ["property_id"], ["codigo_dwv"], ["codigoDwv"], ["codigo"]) ||
        value(payload, ["data", "id"], ["data", "propertyId"], ["data", "property_id"], ["data", "codigo_dwv"], ["data", "codigoDwv"], ["data", "codigo"])
    end

    def self.value(payload, *paths)
      paths.each do |path|
        current = payload
        path.each do |segment|
          if current.is_a?(Hash)
            current = current[segment] || current[segment.to_sym]
          else
            current = nil
          end
          break if current.nil?
        end
        return current unless current.nil?
      end
      nil
    end

    def initialize(payload, tenant: nil)
      @raw_payload = payload || {}
      @payload = unwrap_payload(@raw_payload)
      @tenant = tenant || Current.tenant
      raise ArgumentError, "Tenant obrigatório para Dwv::PropertyImportService" if @tenant.blank?
    end

    def perform
      dwv_id = self.class.extract_property_id(@payload).to_s
      raise "ID do imóvel DWV não encontrado no payload." if dwv_id.blank?

      incoming_codigo = value(["reference"], ["codigo"], ["code"]).to_s.strip

      habitation = find_existing_habitation(dwv_id: dwv_id, codigo: incoming_codigo) || tenant.habitations.new
      existing_record = habitation.persisted?

      if !existing_record && insufficient_payload_for_new_record?
        raise "Payload DWV incompleto para novo cadastro (id=#{dwv_id})."
      end

      assign_habitation_attributes(habitation, dwv_id:, incoming_codigo:, existing_record:)
      address_attrs = extract_address

      Habitation.transaction do
        habitation.save!

        if address_attrs.present?
          address = habitation.address || habitation.build_address
          address.assign_attributes(address_attrs)
          address.save!
        end
      end

      { success: true, habitation: habitation }
    rescue => e
      if defined?(habitation) && habitation&.persisted?
        habitation.update(
          last_sync_at: Time.current,
          last_sync_status: "error",
          last_sync_message: e.message
        )
      end
      raise e
    end

    private

    attr_reader :tenant

    def value(*paths)
      self.class.value(@payload, *paths)
    end

    def unwrap_payload(payload)
      return {} unless payload.is_a?(Hash)

      data = payload["data"] || payload[:data]
      return data if data.is_a?(Hash)

      payload
    end

    def assign_habitation_attributes(habitation, dwv_id:, incoming_codigo:, existing_record:)
      sale_cents = first_cents(
        value(["price"], ["sale_price"], ["valor_venda"], ["unit", "price"], ["third_party_property", "price"])
      )
      rent_cents = first_cents(
        value(["rent_price"], ["valor_locacao"], ["unit", "rent"], ["third_party_property", "rent"])
      )
      effective_sale = sale_cents || habitation.valor_venda_cents
      effective_rent = rent_cents || habitation.valor_locacao_cents

      raw_status = value(["status"], ["property_status"]).to_s.strip.downcase
      raw_integration_status = value(["integration_status"]).to_s.strip.downcase
      derived_status = derive_dwv_status(
        raw_status: raw_status,
        raw_integration_status: raw_integration_status,
        raw_deleted: value(["deleted"]),
        sale_cents: effective_sale,
        rent_cents: effective_rent,
        current_status: habitation.status
      )

      pictures = extract_pictures
      videos = extract_videos
      plantas = extract_floor_plans
      features = extract_features(category: "feature")
      infrastructure = extract_features(category: "infrastructure")
      constructor = find_or_build_constructor
      address_attrs = extract_address
      description = extract_description
      category = inferred_category
      development_name = resolved_development_name(category) || habitation.nome_empreendimento

      attrs = {
        codigo_dwv: dwv_id,
        imovel_dwv: "Sim",
        admin_user: habitation.admin_user || dwv_owner_user,
        status: derived_status,
        valor_venda_cents: effective_sale,
        valor_locacao_cents: effective_rent,
        valor_condominio_cents: first_cents(value(["condominium_fee"], ["valor_condominio"], ["third_party_property", "administration_fee"])) || habitation.valor_condominio_cents,
        valor_iptu_cents: first_cents(value(["property_tax"], ["valor_iptu"], ["third_party_property", "property_tax"])) || habitation.valor_iptu_cents,
        exibir_no_site_flag: active_on_site?,
        titulo_anuncio: text_value(["advertisement_title"], ["title"], ["name"], ["titulo"], ["third_party_property", "title"], ["unit", "title"]) || habitation.titulo_anuncio,
        categoria: category || habitation.categoria || DEFAULT_CATEGORY,
        categoria_grupo: text_value(["unit", "floor_plan", "category", "tag"], ["unit", "additional_category"], ["third_party_property", "additional_category"]) || habitation.categoria_grupo,
        situacao: map_situation(value(["construction_stage_raw"], ["construction_stage"], ["property_condition"], ["situacao"])) || habitation.situacao,
        tipo: detect_record_type || habitation.tipo || "Unitário",
        codigo_empreendimento: local_development_code || habitation.codigo_empreendimento,
        nome_empreendimento: development_name,
        data_entrega: parse_date(value(["building", "delivery_date"], ["third_party_property", "delivery_date"])) || habitation.data_entrega,
        dormitorios_qtd: first_int(value(["bedrooms"], ["unit_bedrooms"], ["quartos"], ["unit", "dorms"], ["third_party_property", "dorms"])) || habitation.dormitorios_qtd,
        suites_qtd: first_int(value(["unit_suites"], ["suites"], ["suites_qtd"], ["unit", "suites"], ["third_party_property", "suites"])) || habitation.suites_qtd,
        banheiros_qtd: first_int(value(["bathrooms"], ["banheiros"], ["total_bathrooms"], ["unit", "bathroom"], ["third_party_property", "bathroom"])) || habitation.banheiros_qtd,
        vagas_qtd: first_int(value(["unit_parking_spaces"], ["parking_spaces"], ["vagas"], ["unit", "parking_spaces"], ["third_party_property", "parking_spaces"])) || habitation.vagas_qtd,
        area_privativa_m2: first_decimal(value(["private_area"], ["unit_private_area"], ["area_privativa"], ["area_privativa_m2"], ["unit", "private_area"], ["third_party_property", "private_area"])) || habitation.area_privativa_m2,
        area_util_m2: first_decimal(value(["util_area"], ["unit", "util_area"], ["third_party_property", "util_area"])) || habitation.area_util_m2,
        area_total_m2: first_decimal(value(["total_area"], ["unit_total_area"], ["area_total"], ["area_total_m2"], ["unit", "total_area"], ["third_party_property", "total_area"])) || habitation.area_total_m2,
        descricao_empreendimento: clean_text(value(["building", "description"])) || habitation.descricao_empreendimento,
        caracteristicas: features.presence || habitation.caracteristicas,
        infra_estrutura: infrastructure.presence || habitation.infra_estrutura,
        pictures: pictures.presence || habitation.pictures,
        fotos_empreendimento: extract_development_pictures.presence || habitation.fotos_empreendimento,
        videos: videos.presence || habitation.videos,
        plantas: plantas.presence || habitation.plantas,
        tour_virtual: text_value(["building", "virtual_tour"], ["building", "tour_360"], ["third_party_property", "virtual_tour"]) || habitation.tour_virtual,
        condicoes_negociacao: extract_payment_conditions || habitation.condicoes_negociacao,
        construtora: text_value(["construction_company", "title"]) || habitation.construtora,
        constructor: constructor || habitation.constructor,
        data_cadastro_crm: habitation.data_cadastro_crm || parse_time(value(["inserted_at"], ["created_at"])),
        data_atualizacao_crm: parse_time(value(["last_updated_at"], ["updated_at"])) || Time.current,
        last_sync_at: Time.current,
        last_sync_status: "success",
        last_sync_message: existing_record ? "Sincronizado via DWV (mapeamento completo)" : "Sincronizado via DWV (cadastro inicial)"
      }
      attrs[:descricao_web] = description if description.present?
      attrs[:dwv_payload] = @payload if habitation.has_attribute?(:dwv_payload)

      attrs.merge!(legacy_address_attrs(address_attrs)) if address_attrs.present?
      attrs.merge!(derived_feature_flags(features + infrastructure))
      attrs[:codigo] = resolve_codigo_for(habitation) unless existing_record

      habitation.assign_attributes(attrs)
    end

    def find_existing_habitation(dwv_id:, codigo:)
      by_dwv_code = tenant.habitations.where(codigo_dwv: dwv_id, imovel_dwv: "Sim")
      return pick_best_candidate(by_dwv_code) if by_dwv_code.exists?

      by_dwv_code_legacy = tenant.habitations.where(codigo_dwv: dwv_id)
      return pick_best_candidate(by_dwv_code_legacy) if by_dwv_code_legacy.exists?

      return nil if codigo.blank?

      by_code_and_dwv_flag = tenant.habitations.where(codigo: codigo, imovel_dwv: "Sim")
      return pick_best_candidate(by_code_and_dwv_flag) if by_code_and_dwv_flag.exists?

      by_code_and_dwv_code = tenant.habitations.where(codigo: codigo).where.not(codigo_dwv: [nil, ""])
      return pick_best_candidate(by_code_and_dwv_code) if by_code_and_dwv_code.exists?

      nil
    end

    def pick_best_candidate(scope)
      scope.order(Arel.sql("CASE WHEN codigo_dwv IS NULL OR codigo_dwv = '' THEN 1 ELSE 0 END"), updated_at: :desc).first
    end

    def dwv_owner_user
      @dwv_owner_user ||= Dwv::OwnerResolver.call(tenant)
    end

    def resolve_codigo_for(habitation)
      current = habitation.codigo.to_s.strip
      current.presence
    end

    def detect_record_type
      return "Unitário" if value(["unit"]).is_a?(Hash) || value(["third_party_property"]).is_a?(Hash)
      return "Empreendimento" if value(["building"]).is_a?(Hash)

      nil
    end

    def local_development_code
      raw_code = text_value(["building", "id"])
      return nil if raw_code.blank?

      tenant.habitations.empreendimentos.exists?(codigo: raw_code) ? raw_code : nil
    end

    def normalize_category(raw)
      category = raw.to_s.strip
      return nil if category.blank?

      known = Habitation::CATEGORIES.find { |item| item.casecmp(category).zero? }
      return known if known.present?

      return "Sala Comercial" if category.match?(/comercial|sala|loja|galp[aã]o|pr[ée]dio/i)
      return "Terreno" if category.match?(/terreno|lote|[áa]rea/i)
      return "Casa" if category.match?(/casa|sobrado/i)

      "Apartamento"
    end

    def inferred_category
      return @inferred_category if defined?(@inferred_category)

      @inferred_category = compute_inferred_category
    end

    def compute_inferred_category
      raw_category = value(
        ["unit", "floor_plan", "category", "title"],
        ["unit", "type"],
        ["unit", "section", "name"],
        ["third_party_property", "type"],
        ["type", "name"],
        ["type"],
        ["category"],
        ["categoria"]
      )
      category = normalize_category(raw_category)
      return "Casa em Condomínio" if category == "Casa" && condominium_context?

      category
    end

    def condominium_context?
      unit_info = text_value(["third_party_property", "unit_info"], ["unit", "unit_info"], ["unit_info"])
      title = text_value(["advertisement_title"], ["title"], ["name"], ["titulo"], ["third_party_property", "title"])

      return true if [dwv_complement, unit_info, title].compact.any? { |t| t.match?(/condom[ií]nio/i) }

      # Nome de empreendimento/residencial no complemento ou unit_info (campos
      # estruturados) também caracteriza casa em condomínio — ex.: "BOULEVARD DA
      # BARRA PARK RESIDENCE", "ED. SAINT PAUL".
      [dwv_complement, unit_info].compact.any? { |t| Dwv::DevelopmentNameInference.development_name?(t) }
    end

    def inferred_condominium_name(category)
      return nil unless category == "Casa em Condomínio"

      title = text_value(["advertisement_title"], ["title"], ["name"], ["titulo"], ["third_party_property", "title"])
      return nil if title.blank?

      title.match(/(condom[ií]nio\s+.+)\z/i)&.[](1)&.squish
    end

    # Nome do empreendimento, em ordem de confiança: empreendimento DWV (building),
    # nome extraído do título de "Casa em Condomínio" e, por fim, o nome inferido do
    # complemento/unit_info quando ele é claramente um empreendimento/residencial.
    def resolved_development_name(category)
      text_value(["building", "title"]).presence ||
        inferred_condominium_name(category).presence ||
        development_name_from_unit_context.presence
    end

    def development_name_from_unit_context
      Dwv::DevelopmentNameInference.call(
        dwv_complement,
        text_value(["third_party_property", "unit_info"], ["unit", "unit_info"], ["unit_info"])
      )
    end

    # Quando o complemento é, na íntegra, o próprio nome do empreendimento promovido,
    # ele deixa de ser um complemento de endereço válido e é removido para não
    # duplicar a informação (endereço x título x empreendimento).
    def complement_promoted_to_development?
      complement = Dwv::DevelopmentNameInference.clean(dwv_complement)
      return false if complement.blank?
      # Complemento com número costuma carregar também o localizador da unidade
      # (ex.: "Casa 12 Residencial X"): preserva o complemento e só promove o nome.
      return false if complement.match?(/\d/)
      # Invariante: nunca esvazia o complemento se o nome não fosse persistir
      # (categorias standalone zeram nome_empreendimento via callback do model).
      return false if Habitation.standalone_category_without_development_name?(inferred_category)
      return false if text_value(["building", "title"]).present?
      return false if inferred_condominium_name(inferred_category).present?

      name = Dwv::DevelopmentNameInference.call(complement)
      name.present? && Dwv::DevelopmentNameInference.fold(name) == Dwv::DevelopmentNameInference.fold(complement)
    end

    def dwv_complement
      return @dwv_complement if defined?(@dwv_complement)

      address = third_party? ? value(["third_party_property", "address"]) : nil
      address = value(["address"]) if !address.is_a?(Hash)
      address = {} unless address.is_a?(Hash)

      @dwv_complement = (self.class.value(address, ["complement"]) || value(["third_party_property", "unit_info"])).to_s.strip.presence
    end

    def map_status(raw)
      status = raw.to_s.strip.downcase
      return nil if status.blank?
      return "Venda" if status.include?("sale") || status.include?("venda")
      return "Aluguel" if status.include?("rent") || status.include?("loca") || status.include?("alug")
      return "Suspenso" if status.include?("inactive") || status.include?("inativo")
      return nil if status == "active"

      Habitation.normalize_status(raw)
    end

    def infer_status_from_prices(sale_cents, rent_cents)
      return "Venda" if sale_cents.to_i.positive?
      return "Aluguel" if rent_cents.to_i.positive?

      nil
    end

    def derive_dwv_status(raw_status:, raw_integration_status:, raw_deleted:, sale_cents:, rent_cents:, current_status:)
      return "Suspenso" if raw_deleted == true || raw_deleted.to_s == "true"

      [raw_status, raw_integration_status].each do |status|
        next if status.blank?
        return "Vendido terceiros" if status == "auto_inactive"
        return "Suspenso" if status == "inactive"
      end

      map_status(raw_status) || infer_status_from_prices(sale_cents, rent_cents) || current_status
    end

    def map_situation(raw)
      status = raw.to_s.strip.downcase
      return nil if status.blank?
      return "Pré Lançamento" if status.include?("pre-market") || status.include?("pre market") || status.include?("pré lançamento") || status.include?("pre lançamento")
      return "Lançamento" if status.include?("launch") || status.include?("lançamento")
      return "Construção" if status.include?("under construction") || status.include?("obra")
      return "Novo" if status == "new"
      return "Usado" if status == "used"

      status.titleize
    end

    def active_on_site?
      raw_status = value(["status"], ["integration_status"]).to_s.downcase
      deleted = value(["deleted"])
      return false if deleted == true || deleted.to_s == "true"
      return false if raw_status == "inactive" || raw_status == "auto_inactive"

      true
    end

    def extract_address
      address = third_party? ? value(["third_party_property", "address"]) : nil
      address = value(["address"]) if !address.is_a?(Hash)
      building_address = value(["building", "address"])
      address = {} unless address.is_a?(Hash)
      building_address = {} unless building_address.is_a?(Hash)

      street = self.class.value(address, ["street"], ["street_name"], ["logradouro"]) ||
               self.class.value(building_address, ["street"], ["street_name"], ["logradouro"]) ||
               value(["street"], ["address"])

      city = self.class.value(address, ["city"]) || self.class.value(building_address, ["city"]) || value(["city"])
      state = self.class.value(address, ["state"], ["uf"]) || self.class.value(building_address, ["state"], ["uf"]) || value(["state"], ["uf"])
      district = self.class.value(address, ["district"], ["neighborhood"], ["bairro"]) ||
                 self.class.value(building_address, ["district"], ["neighborhood"], ["bairro"]) ||
                 value(["neighborhood"], ["bairro"])

      # Se o complemento é, na verdade, o nome do empreendimento (promovido para
      # nome_empreendimento), ele não deve permanecer no endereço.
      complement = complement_promoted_to_development? ? nil : dwv_complement
      building_complement = self.class.value(building_address, ["complement"])

      normalized = {
        tipo_endereco: "Rua",
        logradouro: street.to_s.strip,
        numero: (self.class.value(address, ["number"], ["street_number"]) || self.class.value(building_address, ["number"], ["street_number"])).to_s.strip.presence,
        complemento: complement.to_s.strip.presence,
        bairro: district.to_s.strip,
        cidade: city.to_s.strip,
        uf: state.to_s.strip.upcase.first(2),
        cep: (self.class.value(address, ["zipCode"], ["zip_code"], ["cep"]) || self.class.value(building_address, ["zipCode"], ["zip_code"], ["cep"])).to_s.strip.presence,
        pais: self.class.value(address, ["country"]) || self.class.value(building_address, ["country"]) || "Brasil",
        latitude: first_decimal(self.class.value(address, ["latitude"]) || self.class.value(building_address, ["latitude"]) || value(["latitude"])),
        longitude: first_decimal(self.class.value(address, ["longitude"]) || self.class.value(building_address, ["longitude"]) || value(["longitude"])),
        imediacoes: Array(building_complement.to_s.strip.presence)
      }

      required = normalized.values_at(:logradouro, :bairro, :cidade, :uf)
      return nil if required.any?(&:blank?)

      normalized
    end

    def legacy_address_attrs(address_attrs)
      attrs = address_attrs.except(:logradouro, :imediacoes)
      attrs[:endereco] = address_attrs[:logradouro]
      attrs[:imediacoes] = Array(address_attrs[:imediacoes]).join(", ").presence
      if attrs[:complemento].blank? && !complement_promoted_to_development?
        attrs[:bloco] = text_value(["unit", "title"], ["third_party_property", "unit_info"])
      end
      attrs
    end

    def extract_pictures
      raw_sources = []
      raw_sources << value(["unit", "cover"])
      raw_sources += media_items(value(["unit", "images"]))
      raw_sources += media_items(value(["unit", "pictures"]))
      raw_sources += media_items(value(["unit", "photos"]))
      raw_sources += media_items(value(["third_party_property", "cover"]))
      raw_sources += media_items(value(["third_party_property", "gallery"]))
      raw_sources += media_items(value(["selected_photos"]))
      raw_sources += media_items(value(["images"]))
      raw_sources += media_items(value(["pictures"]))
      raw_sources += media_items(value(["photos"]))
      raw_sources << value(["building", "cover"]) if raw_sources.compact.blank?

      normalize_media_payload(raw_sources, type: "Foto")
    end

    def extract_development_pictures
      raw_sources = []
      raw_sources << value(["building", "cover"])
      raw_sources += Array(value(["building", "gallery"]))
      normalize_media_payload(raw_sources, type: "Foto")
    end

    def extract_videos
      normalize_media_payload(media_items(value(["building", "videos"])) + media_items(value(["building", "video"])) + media_items(value(["videos"])) + media_items(value(["video"])), type: "Vídeo")
    end

    def extract_floor_plans
      normalize_media_payload(media_items(value(["building", "architectural_plans"])) + media_items(value(["unit", "floor_plan", "images"])) + media_items(value(["plantas"])), type: "Planta")
    end

    def normalize_media_payload(raw_sources, type:)
      normalized = raw_sources.flatten.compact.map.with_index do |item, index|
        media_from(item, fallback_order: index + 1, type: type)
      end.compact

      unique = normalized.uniq { |media| media["url"].to_s.strip }
      return [] if unique.blank?

      unique.first["principal"] = true if type == "Foto"
      unique.each_with_index do |media, index|
        media["ordem"] = index + 1 if media["ordem"].to_i <= 0
      end
      unique
    end

    def media_items(raw)
      return [] if raw.blank?
      return raw if raw.is_a?(Array)

      [raw]
    end

    def media_from(item, fallback_order:, type:)
      return if item.nil?
      return { "url" => item, "ordem" => fallback_order, "principal" => false, "tipo" => type } if item.is_a?(String)
      return unless item.is_a?(Hash)

      sizes = item["sizes"] || item[:sizes]
      medium_url = sizes["medium"] || sizes[:medium] || sizes["small"] || sizes[:small] if sizes.is_a?(Hash)
      url = item["url"] || item[:url] || item["image"] || item[:image] || item["file"] || item[:file]
      url = url["url"] || url[:url] if url.is_a?(Hash)
      return if url.blank?

      {
        "url" => url,
        "url_pequena" => item["thumbnail"] || item[:thumbnail] || medium_url,
        "ordem" => item["order"] || item[:order] || fallback_order,
        "principal" => item["featured"] == true || item[:featured] == true,
        "tipo" => type,
        "descricao" => item["title"] || item[:title] || item["description"] || item[:description]
      }.compact
    end

    def extract_description
      clean_text(value(["description_text"], ["description"], ["description_raw"], ["description_html"], ["third_party_property", "description"]))
    end

    def clean_text(raw)
      text = raw.to_s
      return nil if text.blank?

      ActionView::Base.full_sanitizer.sanitize(text).squish.presence
    end

    def extract_payment_conditions
      conditions = value(["unit", "payment_conditions"], ["third_party_property", "payment_conditions"])
      return nil unless conditions.is_a?(Array)

      conditions.filter_map do |condition|
        next unless condition.is_a?(Hash)

        label = condition["name"] || condition[:name] || condition["title"] || condition[:title]
        price = condition["price"] || condition[:price] || condition["value"] || condition[:value]
        [label, price].compact.join(": ").presence
      end.join("\n").presence
    end

    def extract_features(category:)
      source = value(["building", "features"])
      source = value(["third_party_property", "features"]) if !source.is_a?(Array) || source.blank?
      source = value(["features"]) if !source.is_a?(Array) || source.blank?
      return [] unless source.is_a?(Array)

      source.filter_map do |feature|
        next feature.to_s.strip if feature.is_a?(String)
        next unless feature.is_a?(Hash)

        type = feature["type"] || feature[:type] || feature["category"] || feature[:category]
        title = feature["title"] || feature[:title] || feature["name"] || feature[:name] || feature["tag"] || feature[:tag]
        next if title.blank?

        if category == "infrastructure"
          next unless type.to_s.match?(/empreendimento|building|infra|lazer/i)
        else
          next if type.to_s.match?(/empreendimento|building|infra|lazer/i)
        end

        title.to_s.strip
      end.uniq
    end

    def derived_feature_flags(features)
      normalized = features.join(" ").parameterize(separator: " ")
      {
        mobiliado_flag: normalized.include?("mobiliado"),
        decorado_flag: normalized.include?("decorado"),
        piscina_flag: normalized.include?("piscina"),
        varanda_gourmet_flag: normalized.include?("gourmet") || normalized.include?("churrasqueira"),
        garden_flag: normalized.include?("garden") || normalized.include?("jardim"),
        quadra_mar_flag: normalized.include?("quadra mar"),
        frente_mar_avenida_atlantica_flag: normalized.include?("frente mar"),
        vista_frente_mar_flag: normalized.include?("vista mar"),
        lavabo_flag: normalized.include?("lavabo"),
        aceita_permuta_flag: normalized.include?("permuta"),
        aceita_financiamento_flag: normalized.include?("financiamento")
      }
    end

    def find_or_build_constructor
      name = text_value(["construction_company", "title"])
      return nil if name.blank?

      constructor = Constructor.where("LOWER(name) = ?", name.downcase).first_or_initialize(name: name)
      constructor.website_url ||= text_value(["construction_company", "site"])
      constructor.save! if constructor.changed?
      constructor
    end

    def third_party?
      value(["third_party_property"]).is_a?(Hash)
    end

    def text_value(*paths)
      raw = value(*paths)
      raw.to_s.strip.presence
    end

    def first_cents(raw)
      return nil if raw.blank?

      number = normalized_number(raw)
      return nil if number.nil? || number <= 0

      (number * 100).round
    end

    def first_int(raw)
      return nil if raw.blank?

      value = raw.to_i
      value.negative? ? 0 : value
    end

    def first_decimal(raw)
      return nil if raw.blank?

      number = normalized_number(raw)
      return nil if number.nil? || number <= 0

      number
    end

    def normalized_number(raw)
      return raw if raw.is_a?(Numeric)

      text = raw.to_s.gsub(/[^\d,.-]/, "")
      return nil if text.blank?

      if text.include?(",") && text.include?(".")
        text = text.gsub(".", "").tr(",", ".")
      else
        text = text.tr(",", ".")
      end

      BigDecimal(text)
    rescue ArgumentError
      nil
    end

    def parse_date(raw)
      return nil if raw.blank?

      Date.parse(raw.to_s)
    rescue ArgumentError
      nil
    end

    def parse_time(raw)
      return nil if raw.blank?

      Time.zone.parse(raw.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def insufficient_payload_for_new_record?
      return false if active_on_site?

      title_present = text_value(["title"], ["advertisement_title"], ["name"], ["titulo"], ["third_party_property", "title"]).present?
      category_present = text_value(["unit", "type"], ["third_party_property", "type"], ["type", "name"], ["type"], ["category"], ["categoria"]).present?
      has_any_price = first_cents(value(["price"], ["sale_price"], ["valor_venda"], ["unit", "price"], ["third_party_property", "price"])).present? ||
                      first_cents(value(["rent_price"], ["valor_locacao"], ["unit", "rent"], ["third_party_property", "rent"])).present?
      has_location = extract_address.present? ||
                     value(["city"], ["neighborhood"], ["bairro"], ["address", "city"], ["address", "district"]).to_s.strip.present?
      has_pictures = extract_pictures.present?

      !title_present && !category_present && !has_any_price && !has_location && !has_pictures
    end
  end
end
