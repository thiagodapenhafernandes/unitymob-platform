class SyncPropertyService
  VISTA_KEY  = ENV.fetch('VISTA_KEY')  { 'ea83a702a7669520304be011258289fd' }
  VISTA_HOST = ENV.fetch('VISTA_HOST') { 'http://saluteim20174-rest.vistahost.com.br' }
  DETALHES_PATH = '/imoveis/detalhes'
  PRESERVED_MANUAL_MODE_FIELDS = %i[
    status situacao valor_venda_cents valor_locacao_cents valor_condominio_cents valor_iptu_cents
    data_cadastro_crm data_atualizacao_crm pictures last_sync_at last_sync_status last_sync_message
  ].freeze

  def initialize(codigo, host: nil, token: nil, preserve_manual_fields: nil, force_empreendimento: false, detach_orphan_parent: false)
    @codigo = codigo
    @vista_host = host.presence || VISTA_HOST
    @vista_key = token.presence || VISTA_KEY
    @preserve_manual_fields = preserve_manual_fields
    @force_empreendimento = force_empreendimento
    @detach_orphan_parent = detach_orphan_parent
  end

  def perform
    habitation = Habitation.find_or_initialize_by(codigo: @codigo)
    existing_record = habitation.persisted?
    hb = fetch_details(@codigo)
    
    unless hb
      error_message = @last_fetch_error.presence || "Imóvel não encontrado na API"
      habitation.update(last_sync_at: Time.current, last_sync_status: 'error', last_sync_message: error_message) if habitation.persisted?
      return { success: false, error: error_message }
    end

    habitation_attrs, address_attrs = map_vista_payload(hb)
    habitation_attrs = habitation_attrs.merge(
      last_sync_at: Time.current,
      last_sync_status: 'success',
      last_sync_message: "Sincronizado com sucesso"
    )

    Habitation.transaction do
      habitation.assign_attributes(filtered_habitation_attrs(habitation_attrs, existing_record: existing_record))
      habitation.save!

      if sync_address_for?(existing_record: existing_record)
        address = habitation.address || habitation.build_address
        address.assign_attributes(address_attrs)
        address.save!
      end
    end

    sync_dynamic_attribute_options!(
      feature_values: habitation_attrs[:caracteristicas]&.values,
      infrastructure_values: habitation_attrs[:infra_estrutura],
      unique_feature_values: habitation_attrs[:caracteristica_unica],
      imediacoes_values: address_attrs[:imediacoes]
    )

    { success: true, habitation: habitation, created: !existing_record, updated: existing_record }
  rescue ActiveRecord::RecordInvalid => e
    error_msg = e.record.errors.full_messages.join(", ")
    habitation.update(last_sync_at: Time.current, last_sync_status: 'error', last_sync_message: error_msg) if habitation&.persisted?
    { success: false, error: error_msg }
  rescue => e
    habitation.update(last_sync_at: Time.current, last_sync_status: 'error', last_sync_message: e.message) if habitation && habitation.persisted?
    { success: false, error: e.message }
  end

  private

  def fetch_details(codigo)
    payload = {
      'fields' => [
        'TipoEndereco', 'Endereco', 'Numero', 'Bairro', 'BairroComercial', 'Cidade', 'UF', 'CEP', 'Complemento', 'Pais', 'Imediacoes',
        'Latitude', 'Longitude', 'TituloSite', 'Dormitorios', 'Suites', 'TotalBanheiros', 'Vagas',
        'AreaPrivativa', 'AreaTotal', 'Status', 'Situacao', 'ValorVenda', 'ValorLocacao',
        'ValorCondominio', 'ValorIptu', 'Empreendimento', 'CodigoEmpreendimento', 'Lancamento',
        'DescricaoWeb', 'CaracteristicaUnica', 'Caracteristicas', 'InfraEstrutura', 'ExibirNoSite', 'DestaqueWeb', 'Categoria', 'Construtora',
        'Proprietario', 'CodigoProprietario',
        { 'proprietarios' => ['Nome', 'Email', 'Celular', 'FoneComercial', 'FoneResidencial'] },
        'Corretor', 'CodigoCorretor',
        'DataCadastro', 'DataAtualizacao', 'DataEntrega', { 'Foto' => ['Foto', 'FotoPequena', 'Destaque', 'Ordem'] }
      ]
    }

    url = "#{@vista_host}#{DETALHES_PATH}"
    params = {
      key: @vista_key,
      imovel: codigo,
      pesquisa: payload.to_json,
      showSuspended: 1
    }
    
    response = RestClient.get(url, params: params, accept: :json)
    parsed = JSON.parse(response.body)
    return parsed if parsed.is_a?(Hash)

    raise "Resposta inválida ao consultar detalhes do imóvel #{@codigo}."
  rescue RestClient::ExceptionWithResponse => e
    body = e.response&.body.to_s
    parsed_error = JSON.parse(body) rescue {}
    api_message = parsed_error["message"].presence || parsed_error["msg"].presence
    @last_fetch_error = "Falha ao consultar imóvel #{@codigo} na API Loft: #{api_message.presence || e.response&.code || e.message}"
    nil
  rescue JSON::ParserError
    @last_fetch_error = "Resposta inválida da API Loft ao consultar imóvel #{@codigo}."
    nil
  rescue StandardError => e
    @last_fetch_error = "Erro ao consultar imóvel #{@codigo} na API Loft: #{e.message}"
    nil
  end

  def map_vista_payload(hb)
    categoria = hb['Categoria'].to_s.strip
    is_empreendimento = @force_empreendimento || categoria.casecmp("Empreendimento").zero?
    tipo = is_empreendimento ? "Empreendimento" : "Unitário"
    constructor_id = resolve_constructor(hb['Construtora'])
    owner_data = extract_owner_data(hb['proprietarios'])
    proprietor = resolve_proprietor(hb, owner_data)
    broker_id = resolve_broker(hb)
    raw_imediacoes = hb['Imediacoes']
    codigo_empreendimento = @detach_orphan_parent ? nil : hb['CodigoEmpreendimento'].to_s.strip.presence
    nome_empreendimento = development_name_from_vista(
      categoria,
      codigo_empreendimento,
      hb['Empreendimento'].to_s.strip.presence
    )

    habitation_attrs = {
      titulo_anuncio: hb['TituloSite'],
      categoria: categoria.presence,
      tipo: tipo,
      status: Habitation.normalize_status(hb['Status']),
      situacao: hb['Situacao'],
      endereco: hb['Endereco'],
      numero: hb['Numero'],
      bairro: hb['Bairro'],
      cidade: hb['Cidade'],
      uf: hb['UF'],
      cep: hb['CEP'],
      dormitorios_qtd: hb['Dormitorios'].to_i,
      suites_qtd: hb['Suites'].to_i,
      banheiros_qtd: hb['TotalBanheiros'].to_i,
      vagas_qtd: hb['Vagas'].to_i,
      area_privativa_m2: hb['AreaPrivativa'].to_f,
      area_total_m2: hb['AreaTotal'].to_f,
      valor_venda_cents: parse_money(hb['ValorVenda']),
      valor_locacao_cents: parse_money(hb['ValorLocacao']),
      valor_condominio_cents: parse_money(hb['ValorCondominio']),
      valor_iptu_cents: parse_money(hb['ValorIptu']),
      caracteristica_unica: normalize_csv_list(hb['CaracteristicaUnica']),
      caracteristicas: extract_characteristics(hb),
      infra_estrutura: extract_infrastructure(hb),
      codigo_empreendimento: codigo_empreendimento,
      nome_empreendimento: nome_empreendimento,
      construtora: hb['Construtora'].to_s.strip.presence,
      constructor_id: constructor_id,
      admin_user_id: broker_id,
      proprietor_id: proprietor&.id,
      proprietario: proprietor&.name,
      proprietario_codigo: proprietor&.vista_code,
      proprietario_email: proprietor&.email,
      proprietario_celular: proprietor&.mobile_phone,
      proprietario_telefone_comercial: proprietor&.business_phone,
      proprietario_telefone_residencial: proprietor&.residential_phone,
      exibir_no_site_flag: hb['ExibirNoSite'] == 'Sim',
      destaque_web_flag: hb['DestaqueWeb'] == 'Sim',
      lancamento_flag: hb['Lancamento'] == 'Sim',
      data_cadastro_crm: parse_datetime_value(hb['DataCadastro']),
      data_atualizacao_crm: parse_datetime_value(hb['DataAtualizacao']) || Time.current,
      pictures: format_photos(hb['Foto'])
    }

    address_attrs = {
      tipo_endereco: hb['TipoEndereco'],
      logradouro: hb['Endereco'],
      numero: hb['Numero'],
      complemento: hb['Complemento'],
      bairro: hb['Bairro'],
      bairro_comercial: hb['BairroComercial'],
      cidade: hb['Cidade'],
      uf: hb['UF'],
      cep: hb['CEP'],
      pais: hb['Pais'].presence || "Brasil",
      latitude: hb['Latitude'],
      longitude: hb['Longitude'],
      imediacoes: normalize_imediacoes(raw_imediacoes)
    }

    [habitation_attrs, address_attrs]
  end

  def development_name_from_vista(category, development_code, raw_name)
    return nil if raw_name.blank?
    return raw_name if development_code.present?
    return nil if Habitation.standalone_category_without_development_name?(category)

    raw_name
  end

  def parse_money(v)
    return nil if v.blank?
    clean = v.to_s.gsub(/[^\d.,]/, '').tr(',', '.')
    (clean.to_f * 100).to_i
  end

  def parse_datetime_value(raw)
    return nil if raw.blank?

    Time.zone.parse(raw.to_s)
  rescue StandardError
    nil
  end

  def preserve_manual_fields?
    return ActiveModel::Type::Boolean.new.cast(@preserve_manual_fields) unless @preserve_manual_fields.nil?

    Setting.get("loft_preserve_manual_fields", "true") == "true"
  rescue StandardError
    true
  end

  def filtered_habitation_attrs(attrs, existing_record:)
    filtered_attrs = attrs.dup
    filtered_attrs.delete(:exibir_no_site_flag) if existing_record

    return filtered_attrs unless existing_record
    return filtered_attrs unless preserve_manual_fields?

    filtered_attrs.slice(*PRESERVED_MANUAL_MODE_FIELDS)
  end

  def sync_address_for?(existing_record:)
    return true unless existing_record

    !preserve_manual_fields?
  end

  def format_photos(photos_data)
    return [] if photos_data.blank?
    photos_array = photos_data.is_a?(Hash) ? photos_data.values : Array(photos_data)
    
    photos_array.map.with_index do |photo, index|
      next unless photo.is_a?(Hash)
      {
        url: photo['Foto'],
        url_pequena: photo['FotoPequena'],
        principal: photo['Destaque'] == 'Sim',
        ordem: photo['Ordem']&.to_i || index + 1
      }
    end.compact
  end

  def normalize_imediacoes(raw_value)
    case raw_value
    when Array
      raw_value
    when String
      raw_value.split(/[,\n;]+/)
    else
      Array(raw_value)
    end.map { |item| item.to_s.strip }.reject(&:blank?).uniq
  end

  def resolve_constructor(name)
    normalized_name = name.to_s.strip
    return nil if normalized_name.blank?

    constructor = Constructor.where("lower(name) = lower(?)", normalized_name).first
    constructor ||= Constructor.create!(name: normalized_name)
    constructor.id
  rescue
    nil
  end

  # Mapeia corretor responsável do Vista → AdminUser local via vista_id.
  # Preserva valor atual se não conseguir resolver (não sobrescreve com nil).
  def resolve_broker(hb)
    code = hb['CodigoCorretor'].to_s.strip.presence
    return current_broker_id if code.blank?

    user = AdminUser.find_by(vista_id: code)
    user&.id || current_broker_id
  end

  def current_broker_id
    Habitation.where(codigo: @codigo).limit(1).pluck(:admin_user_id).first
  end

  def resolve_proprietor(hb, owner_data = {})
    proprietor_name = owner_data['Nome'].presence || hb['Proprietario'].presence || hb['Construtora'].presence
    proprietor_code = hb['CodigoProprietario'].to_s.strip.presence
    return nil if proprietor_name.to_s.strip.blank?

    role = hb['Proprietario'].present? ? :owner : :developer

    proprietor = nil
    proprietor = Proprietor.find_by(vista_code: proprietor_code) if proprietor_code.present?
    proprietor ||= Proprietor.where("lower(name) = lower(?)", proprietor_name.to_s.strip).first
    proprietor ||= Proprietor.new

    proprietor.name = proprietor_name.to_s.strip
    proprietor.role = role
    proprietor.vista_code = proprietor_code if proprietor_code.present?
    proprietor.email = owner_data['Email'].to_s.strip.presence if owner_data['Email'].to_s.strip.present?
    proprietor.mobile_phone = owner_data['Celular'].to_s.strip.presence if owner_data['Celular'].to_s.strip.present?
    proprietor.business_phone = owner_data['FoneComercial'].to_s.strip.presence if owner_data['FoneComercial'].to_s.strip.present?
    proprietor.residential_phone = owner_data['FoneResidencial'].to_s.strip.presence if owner_data['FoneResidencial'].to_s.strip.present?
    proprietor.save!
    proprietor
  rescue
    nil
  end

  def extract_owner_data(raw_owner_data)
    case raw_owner_data
    when Hash
      first_value = raw_owner_data.values.first
      first_value.is_a?(Hash) ? first_value : {}
    when Array
      raw_owner_data.find { |item| item.is_a?(Hash) } || {}
    else
      {}
    end
  end

  def extract_characteristics(data)
    return {} unless data['Caracteristicas'].is_a?(Hash)

    data['Caracteristicas'].each_with_object({}) do |(key, value), acc|
      next unless value.to_s.casecmp("sim").zero?

      label = key.to_s.strip
      next if label.blank?

      acc[label] = label
    end
  end

  def extract_infrastructure(data)
    return [] unless data['InfraEstrutura'].is_a?(Hash)

    data['InfraEstrutura'].each_with_object([]) do |(key, value), acc|
      label = key.to_s.strip
      acc << label if value.to_s.casecmp("sim").zero? && label.present?
    end.uniq
  end

  def normalize_csv_list(value)
    case value
    when Array
      value
    when String
      value.split(/[,\n;]+/)
    else
      Array(value)
    end.map { |item| item.to_s.strip }.reject(&:blank?).uniq
  end

  def sync_dynamic_attribute_options!(feature_values:, infrastructure_values:, unique_feature_values:, imediacoes_values:)
    now = Time.current
    rows = []
    rows.concat(build_attribute_rows(feature_values, "feature", now))
    rows.concat(build_attribute_rows(infrastructure_values, "infrastructure", now))
    rows.concat(build_attribute_rows(unique_feature_values, "unique_feature", now))
    rows.concat(build_attribute_rows(imediacoes_values, "imediacoes", now))
    return if rows.empty?

    AttributeOption.insert_all(rows, unique_by: :index_attribute_options_on_context_category_lower_name)
  rescue
    nil
  end

  def build_attribute_rows(values, category, now)
    normalize_csv_list(values).map do |name|
      { context: "habitation", category: category, name: name, created_at: now, updated_at: now }
    end
  end
end
