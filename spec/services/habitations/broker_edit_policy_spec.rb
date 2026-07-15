require "rails_helper"

RSpec.describe Habitations::BrokerEditPolicy do
  let(:habitation) { build(:habitation, proprietario_email: nil, proprietario_cidade: nil) }

  def filter(params)
    described_class.filter(params.stringify_keys, habitation: habitation).keys
  end

  it "permite os campos previstos na matriz do card #1" do
    allowed = %w[
      status situacao ocupacao_status estado_conservacao motivo_suspensao
      data_entrega perfil_construcao imediacoes
      dormitorios_qtd vagas_qtd area_privativa_m2 face
      valor_venda_formatted valor_locacao_formatted valor_condominio_formatted
      destaque_web_flag caracteristica_unica caracteristicas
      construtora andares_qtd infra_estrutura
      condicoes_negociacao aceita_permuta_flag rental_guarantee_method
      key_location zelador_nome responsavel_reserva
      photos ordered_photo_ids videos
    ]
    expect(filter(allowed.index_with { "x" })).to match_array(allowed)
  end

  it "bloqueia o que o card #1 diz que o corretor NÃO pode alterar" do
    blocked = %w[
      tipo categoria
      codigo_empreendimento nome_empreendimento
      address_attributes logradouro numero bairro cidade uf complemento bloco lote
      public_map_display_mode public_street_view_mode
      publicar_zapimoveis publicar_lais_ai tipo_publicacao_viva_real
      regiao_foco
      proprietario proprietario_celular captador_commission_percentage
      broker_commission_percentage valor_comissao_formatted valor_livre_proprietario_formatted
      admin_user_id
      meta_title meta_keywords meta_description slug
      foto_classificacao
      titulo_anuncio descricao_web
    ]
    expect(filter(blocked.index_with { "x" })).to be_empty
  end

  it "libera SOMENTE Imediações dentro do endereço (card #1)" do
    params = {
      "address_attributes" => {
        "imediacoes" => ["Praia", "Shopping"],
        "logradouro" => "Rua Nova",
        "numero" => "123",
        "cidade" => "Itajaí",
        "id" => "9"
      }
    }
    result = described_class.filter(params, habitation: habitation)
    expect(result["address_attributes"].keys).to match_array(%w[imediacoes id])
    expect(result["address_attributes"]).not_to have_key("logradouro")
    expect(result["address_attributes"]).not_to have_key("cidade")
  end

  it "não cria address_attributes quando só vieram campos de endereço bloqueados" do
    params = { "address_attributes" => { "logradouro" => "Rua X", "cidade" => "BC" } }
    expect(described_class.filter(params, habitation: habitation)).not_to have_key("address_attributes")
  end

  it "deixa o corretor preencher e-mail/cidade do proprietário só quando vazios" do
    expect(filter("proprietario_email" => "a@b.com", "proprietario_cidade" => "Itajaí"))
      .to match_array(%w[proprietario_email proprietario_cidade])
  end

  it "não deixa sobrescrever e-mail/cidade do proprietário já preenchidos" do
    filled = build(:habitation, proprietario_email: "ja@tem.com", proprietario_cidade: "BC")
    keys = described_class.filter({ "proprietario_email" => "novo@x.com", "proprietario_cidade" => "Itajaí" }, habitation: filled).keys
    expect(keys).to be_empty
  end
end
