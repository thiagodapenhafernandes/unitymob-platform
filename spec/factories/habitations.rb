FactoryBot.define do
  factory :habitation do
    tenant { Current.tenant || Tenant.default }
    sequence(:codigo) { |n| "SPEC-#{n}-#{SecureRandom.hex(4)}" }
    categoria { "Casa em Condomínio" }
    tipo { "Unitário" }
    status { "Venda" }
    endereco { "Rua 1000" }
    exibir_no_site_flag { true }
    valor_venda_cents { 990_000_000 }
    valor_locacao_cents { 0 }
    pictures do
      [
        {
          "url" => "#{Storage::PublicPropertyPhoto.public_base_url}/spec/property.jpg",
          "ordem" => 1,
          "principal" => true
        }
      ]
    end

    after(:build) do |habitation|
      habitation.build_address(
        logradouro: habitation.endereco.presence || "Rua 1000",
        bairro: "Centro",
        cidade: "Balneário Camboriú",
        uf: "SC",
        pais: "Brasil"
      ) unless habitation.address
    end

    trait :unavailable do
      exibir_no_site_flag { false }
    end

    trait :broker_intake do
      intake_origin { Habitation::INTAKE_ORIGIN_BROKER }
      intake_status { "draft" }
      exibir_no_site_flag { false }
      titulo_anuncio { "Casa em Condomínio 2 dormitórios em Centro" }
      descricao_web { "Descrição do imóvel revisada para publicação no site." }
      nome_empreendimento { "Residencial Teste" }
      proprietario { "Proprietário Teste" }
      proprietario_celular { "(47) 99999-0000" }
      valor_venda_cents { 1_000_000_00 }
      valor_condominio_cents { 500_00 }
      valor_iptu_cents { 100_00 }
      area_privativa_m2 { 80 }
      dormitorios_qtd { 2 }
      vagas_qtd { 1 }
      ocupacao_status { "Desocupado" }
      situacao { "Usado" }
      caracteristicas { ["Sacada"] }
      infra_estrutura { ["Piscina"] }
      aceita_permuta_answer { "nao" }
      rental_guarantee_method { "Seguro fiança" }
      key_location { "Proprietário" }
      observacoes_visitas do
        "Cidade do proprietário: Balneário Camboriú\nDias/horários para visita: Seg, Manhã"
      end
      photo_flow_choice { "schedule" }
      photo_session_requested_at { 1.day.from_now }
    end
  end
end
