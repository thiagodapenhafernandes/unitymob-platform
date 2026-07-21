require "rails_helper"

RSpec.describe Habitation, type: :model do
  describe ".next_automatic_codigo" do
    it "continues the CRM sequence after the highest imported Vista reference" do
      reference_codigo = (described_class.highest_numeric_codigo + 100).to_s
      create(:habitation, codigo: reference_codigo, imovel_dwv: "Nao", last_sync_message: "Importado do dump Vista")
      create(:habitation, codigo: "DWV-9999", imovel_dwv: "Sim")

      expect(described_class.next_automatic_codigo).to eq((reference_codigo.to_i + 1).to_s)
    end

    it "skips numeric codes that are already occupied" do
      reference_codigo = described_class.highest_numeric_codigo + 100
      create(:habitation, codigo: reference_codigo.to_s, imovel_dwv: "Nao", last_sync_message: "Importado do dump Vista")
      create(:habitation, codigo: (reference_codigo + 1).to_s, imovel_dwv: "Nao")

      expect(described_class.next_automatic_codigo).to eq((reference_codigo + 2).to_s)
    end
  end

  describe "#assign_codigo_automaticamente" do
    it "fills blank codigo with the next CRM sequence value on create" do
      reference_codigo = (described_class.highest_numeric_codigo + 100).to_s
      create(:habitation, codigo: reference_codigo, imovel_dwv: "Nao", last_sync_message: "Importado do dump Vista")

      habitation = described_class.create!(categoria: "Apartamento")

      expect(habitation.codigo).to eq((reference_codigo.to_i + 1).to_s)
    end
  end

  describe "#data_cadastro_crm" do
    it "sets the registration date on create when it is blank" do
      habitation = described_class.create!(categoria: "Apartamento")

      expect(habitation.data_cadastro_crm).to be_present
    end

    it "keeps an imported registration date when present" do
      imported_at = 3.years.ago.change(usec: 0)
      habitation = described_class.create!(categoria: "Apartamento", data_cadastro_crm: imported_at)

      expect(habitation.data_cadastro_crm.to_i).to eq(imported_at.to_i)
    end
  end

  describe "dados do proprietário" do
    it "prefere o cadastro vinculado aos campos legados do imóvel" do
      proprietor = create(
        :proprietor,
        name: "Proprietário Canônico",
        email: "canonico@example.com",
        mobile_phone: "47 98868.0402",
        business_phone: "47 3344.5566",
        residential_phone: "47 3355.6677",
        vista_code: "PROP-CANONICO"
      )
      habitation = build(
        :habitation,
        proprietor: proprietor,
        proprietario: "Proprietário Legado",
        proprietario_email: "legado@example.com",
        proprietario_celular: "47 99999.0000",
        proprietario_telefone_comercial: "47 3000.0000",
        proprietario_telefone_residencial: "47 4000.0000",
        proprietario_codigo: "PROP-LEGADO"
      )

      expect(habitation.proprietario_nome).to eq("Proprietário Canônico")
      expect(habitation.proprietario_email_display).to eq("canonico@example.com")
      expect(habitation.proprietario_telefone).to eq("5547988680402")
      expect(habitation.proprietario_telefone_comercial_display).to eq("554733445566")
      expect(habitation.proprietario_telefone_residencial_display).to eq("554733556677")
      expect(habitation.proprietario_cpf_cnpj).to eq("PROP-CANONICO")
    end
  end

  describe "third-party commercial values" do
    it "stores formatted third-party values in cents" do
      habitation = described_class.new(
        valor_alugado_terceiros_formatted: "R$ 4.500,00",
        valor_vendido_terceiros_formatted: "R$ 980.000,00"
      )

      expect(habitation.valor_alugado_terceiros_cents).to eq(450_000)
      expect(habitation.valor_vendido_terceiros_cents).to eq(98_000_000)
    end

    it "clears formatted money values when the submitted value is blank" do
      habitation = create(:habitation, valor_venda_cents: 500_000_00)

      habitation.update!(valor_venda_formatted: "")

      expect(habitation.reload.valor_venda_cents).to be_nil
    end
  end

  describe "exchange component values" do
    it "stores vehicle and other item values in cents" do
      habitation = described_class.new(
        permuta_veiculo_valor_formatted: "R$ 85.000,00",
        permuta_outros_valor_formatted: "R$ 12.500,00"
      )

      expect(habitation.permuta_veiculo_valor_cents).to eq(8_500_000)
      expect(habitation.permuta_outros_valor_cents).to eq(1_250_000)
    end

    it "does not revert the commercial exchange flag from an old intake answer" do
      habitation = create(:habitation, aceita_permuta_answer: "nao", aceita_permuta_flag: false)

      habitation.update!(aceita_permuta_flag: true)

      expect(habitation.reload.aceita_permuta_flag).to be(true)
    end

    it "syncs the commercial exchange flag when the intake answer changes" do
      habitation = create(:habitation, aceita_permuta_answer: "nao", aceita_permuta_flag: false)

      habitation.update!(aceita_permuta_answer: "sim")

      expect(habitation.reload.aceita_permuta_flag).to be(true)
    end

    it "does not revert commercial flags when unchanged characteristics are present" do
      habitation = create(
        :habitation,
        caracteristicas: ["Sacada"],
        aceita_financiamento_flag: false,
        aceita_permuta_flag: false
      )

      habitation.update!(aceita_financiamento_flag: true, aceita_permuta_flag: true)

      expect(habitation.reload).to have_attributes(
        aceita_financiamento_flag: true,
        aceita_permuta_flag: true
      )
    end

    it "keeps explicit commercial flags when characteristics are updated in the same save" do
      habitation = create(
        :habitation,
        caracteristicas: ["Sacada"],
        aceita_financiamento_flag: false,
        aceita_permuta_flag: false
      )

      habitation.update!(
        caracteristicas: ["Sacada", "Lavabo"],
        aceita_financiamento_flag: true,
        aceita_permuta_flag: true
      )

      expect(habitation.reload).to have_attributes(
        aceita_financiamento_flag: true,
        aceita_permuta_flag: true,
        lavabo_flag: true
      )
    end
  end

  describe "broker intake address complement rules" do
    it "requires complement for category-specific intakes without treating street houses as mandatory complement" do
      expect(described_class.new(categoria: "Apartamento")).to be_requires_intake_address_complement
      expect(described_class.new(categoria: "Casa em Condomínio")).to be_requires_intake_address_complement
      expect(described_class.new(categoria: "Sala Comercial")).to be_requires_intake_address_complement
      expect(described_class.new(categoria: "Terreno")).to be_requires_intake_address_complement
      expect(described_class.new(categoria: "Casa")).not_to be_requires_intake_address_complement
    end

    it "uses complement and block to identify land lots when present" do
      land_with_complement = described_class.new(categoria: "Terreno")
      land_with_complement.build_address(complemento: "Lote 106")
      land_with_block = described_class.new(categoria: "Terreno", bloco: "Quadra B")

      expect(land_with_complement.duplicate_identity_scope).to eq(:condominium_unit)
      expect(land_with_block.duplicate_identity_scope).to eq(:condominium_unit)
      expect(described_class.new(categoria: "Terreno").duplicate_identity_scope)
        .to eq(:street)
    end

    it "allows the owner broker or assigned broker to release a broker intake" do
      owner = create(:admin_user)
      assigned = create(:admin_user)
      outsider = create(:admin_user)
      habitation = create(:habitation, :broker_intake, admin_user: owner, intake_status: "admin_approved")
      habitation.broker_assignments.create!(admin_user: assigned, role: "captador")

      expect(habitation).to be_broker_release_pending
      expect(habitation.broker_responsible_for?(owner)).to be(true)
      expect(habitation.broker_responsible_for?(assigned)).to be(true)
      expect(habitation.broker_responsible_for?(outsider)).to be(false)
    end

    it "replaces a temporary broker intake code and uses the submission date as registration date" do
      baseline_codigo = (described_class.highest_numeric_codigo + 100).to_s
      create(:habitation, codigo: baseline_codigo)
      submitted_at = Time.zone.local(2026, 7, 16, 10, 30, 0)
      old_registration_date = submitted_at - 7.days
      expected_codigo = described_class.next_automatic_codigo
      habitation = create(
        :habitation,
        :broker_intake,
        codigo: nil,
        data_cadastro_crm: old_registration_date
      )

      expect(habitation.codigo).to start_with(described_class::TEMPORARY_CODIGO_PREFIX)

      habitation.finalize_broker_intake_registration!(submitted_at: submitted_at)

      expect(habitation.codigo).to eq(expected_codigo)
      expect(habitation.data_cadastro_crm).to eq(submitted_at)
    end
  end

  describe "#inactive_for_admin_card?" do
    it "does not mark active internal properties as inactive cards" do
      habitation = described_class.new(status: "Aluguel", exibir_no_site_flag: false)

      expect(habitation).not_to be_inactive_for_admin_card
    end

    it "marks unavailable statuses as inactive cards" do
      expect(described_class.new(status: "Suspenso", exibir_no_site_flag: true)).to be_inactive_for_admin_card
      expect(described_class.new(status: "Vendido terceiros", exibir_no_site_flag: true)).to be_inactive_for_admin_card
      expect(described_class.new(status: "Alugado imobiliária", exibir_no_site_flag: true)).to be_inactive_for_admin_card
    end
  end

  describe "#unavailable_for_duplicate_check?" do
    it "keeps hidden-from-site properties unavailable for duplicate blocking" do
      habitation = described_class.new(status: "Aluguel", exibir_no_site_flag: false)

      expect(habitation).to be_unavailable_for_duplicate_check
    end
  end

  describe "development hierarchy sync" do
    it "copies public development data without replacing the unit broker" do
      development_broker = create(:admin_user)
      unit_broker = create(:admin_user)
      development = create(
        :habitation,
        codigo: "DEV-SYNC-#{SecureRandom.hex(6)}",
        tipo: "Empreendimento",
        admin_user: development_broker,
        nome_empreendimento: "Edifício Atlântico",
        descricao_empreendimento: "Descrição pública do empreendimento.",
        pictures: [{ "url" => "https://cdn.saluteimoveis.com.br/empreendimento.jpg" }]
      )
      development.address.update!(
        bairro: "Centro",
        bairro_comercial: "Barra Sul",
        cidade: "Balneário Camboriú"
      )

      unit = create(
        :habitation,
        codigo: "UNIT-SYNC-#{SecureRandom.hex(6)}",
        admin_user: unit_broker,
        codigo_empreendimento: development.codigo,
        use_development_photos_flag: false,
        nome_empreendimento: nil,
        descricao_empreendimento: nil,
        pictures: []
      )

      expect(unit.reload).to have_attributes(
        admin_user_id: unit_broker.id,
        nome_empreendimento: "Edifício Atlântico",
        descricao_empreendimento: "Descrição pública do empreendimento.",
        use_development_photos_flag: true
      )
      expect(unit.bairro_comercial).to eq("Barra Sul")
      expect(unit.public_neighborhood).to eq("Barra Sul")
    end
  end

  describe "public presentation helpers" do
    it "uses commercial neighborhood and whole currency values for public cards" do
      habitation = build(
        :habitation,
        valor_venda_cents: 1_590_000_99,
        valor_locacao_cents: 0
      )
      habitation.address.bairro = "Centro"
      habitation.address.bairro_comercial = "Barra Sul"
      habitation.address.cidade = "Balneário Camboriú"

      expect(habitation.public_neighborhood).to eq("Barra Sul")
      expect(habitation.short_address).to eq("Barra Sul, Balneário Camboriú")
      expect(habitation.preco_principal).to eq("R$ 1.590.001")
    end
  end

  describe "photo environment ordering" do
    it "uses manual environment positions before current gallery order" do
      habitation = create(:habitation, codigo: "PHOTO-ENV-#{SecureRandom.hex(6)}")
      habitation.photos.attach(io: StringIO.new("quarto dois"), filename: "quarto-2.jpg", content_type: "image/jpeg")
      habitation.photos.attach(io: StringIO.new("quarto um"), filename: "quarto-1.jpg", content_type: "image/jpeg")
      habitation.photos.attach(io: StringIO.new("quarto sem posicao"), filename: "quarto-auto.jpg", content_type: "image/jpeg")
      habitation.photos.attach(io: StringIO.new("banheiro um"), filename: "banheiro-1.jpg", content_type: "image/jpeg")
      attachments = habitation.photos.attachments.order(:id).to_a

      habitation.set_photo_ambiente!(attachments[0], "Quartos", position: 2)
      habitation.set_photo_ambiente!(attachments[1], "Quartos", position: 1)
      habitation.set_photo_ambiente!(attachments[2], "Quartos")
      habitation.set_photo_ambiente!(attachments[3], "Banheiros", position: 1)

      habitation.organize_photos_by_ambiente!

      expect(habitation.reload.photo_ids_order).to eq([
        attachments[1].id,
        attachments[3].id,
        attachments[0].id,
        attachments[2].id
      ])
    end

    it "clears manual position when the environment is cleared" do
      habitation = create(:habitation, codigo: "PHOTO-ENV-CLEAR-#{SecureRandom.hex(6)}")
      habitation.photos.attach(io: StringIO.new("foto"), filename: "foto.jpg", content_type: "image/jpeg")
      attachment = habitation.photos.attachments.first

      habitation.set_photo_ambiente!(attachment, "Quartos", position: 3)
      habitation.set_photo_ambiente!(attachment, "")

      metadata = attachment.blob.reload.metadata
      expect(metadata).not_to have_key("ambiente")
      expect(metadata).not_to have_key("ambiente_position")
    end

    it "stores and organizes environments for external API pictures" do
      habitation = create(
        :habitation,
        codigo: "PIC-ENV-#{SecureRandom.hex(6)}",
        pictures: [
          { "url" => "https://example.com/quarto-2.jpg" },
          { "url" => "https://example.com/fachada.jpg" },
          { "url" => "https://example.com/quarto-1.jpg" },
          { "url" => "https://example.com/banheiro-1.jpg" }
        ]
      )

      habitation.set_picture_ambiente!(0, "Quartos", position: 2)
      habitation.set_picture_ambiente!(1, "Fachada")
      habitation.set_picture_ambiente!(2, "Quartos", position: 1)
      habitation.set_picture_ambiente!(3, "Banheiros", position: 1)

      habitation.organize_photos_by_ambiente!

      expect(habitation.reload.pictures.map { |picture| picture["url"] }).to eq([
        "https://example.com/fachada.jpg",
        "https://example.com/quarto-1.jpg",
        "https://example.com/banheiro-1.jpg",
        "https://example.com/quarto-2.jpg"
      ])
      expect(habitation.picture_ambiente_label(habitation.pictures.second, index: 1)).to eq("Quarto 1")
      expect(habitation.picture_ambiente_label(habitation.pictures.third, index: 2)).to eq("Banheiro 1")
    end
  end

  describe "inactive commercial status publication rules" do
    it "requires suspension reason and disables site and portal publication" do
      habitation = build(
        :habitation,
        status: "Suspenso",
        motivo_suspensao: nil,
        exibir_no_site_flag: true,
        publicar_lais_ai: true,
        publicar_imovelweb: true,
        publicar_imovelweb_2: true,
        publicar_chaves_na_mao: true,
        publicar_casa_mineira: true,
        publicar_viva_real_vrsync: true,
        publicar_loft: true
      )

      expect(habitation).not_to be_valid
      expect(habitation.errors[:motivo_suspensao]).to include("deve ser informado quando o status estiver Suspenso")
      expect(habitation.exibir_no_site_flag).to be(false)
      expect(habitation.publicar_lais_ai).to be(false)
      expect(habitation.publicar_imovelweb).to be(false)
      expect(habitation.publicar_imovelweb_2).to be(false)
      expect(habitation.publicar_chaves_na_mao).to be(false)
      expect(habitation.publicar_casa_mineira).to be(false)
      expect(habitation.publicar_viva_real_vrsync).to be(false)
      expect(habitation.publicar_loft).to be(false)
    end

    it "requires rented value for rented statuses" do
      habitation = build(:habitation, status: "Alugado terceiros", valor_alugado_terceiros_cents: nil)

      expect(habitation).not_to be_valid
      expect(habitation.errors[:valor_alugado_terceiros_cents]).to include("deve ser informado quando o status estiver Alugado")
    end

    it "requires sold value for sold statuses" do
      habitation = build(:habitation, status: "Vendido terceiros", valor_vendido_terceiros_cents: nil)

      expect(habitation).not_to be_valid
      expect(habitation.errors[:valor_vendido_terceiros_cents]).to include("deve ser informado quando o status estiver Vendido")
    end
  end

  describe "#intake_missing_requirements" do
    it "does not force owner city when the operational checklist does not require it" do
      habitation = build(:habitation, :broker_intake, observacoes_visitas: nil)

      missing = habitation.intake_missing_requirements(required_checks: %w[proprietario], require_owner_city: true)

      expect(missing).not_to include("Cidade do proprietário")
    end

    it "requires development name for apartment intakes even outside the operational checklist" do
      habitation = build(:habitation, :broker_intake, categoria: "Apartamento", nome_empreendimento: nil)

      missing = habitation.intake_missing_requirements(required_checks: %w[proprietario])

      expect(missing).to include("Empreendimento")
    end

    it "accepts a manually informed development name without a linked development code" do
      habitation = build(
        :habitation,
        :broker_intake,
        categoria: "Apartamento",
        codigo_empreendimento: nil,
        nome_empreendimento: "Residencial Manual"
      )

      missing = habitation.intake_missing_requirements(required_checks: %w[proprietario])

      expect(missing).not_to include("Empreendimento")
    end

    it "assumes blank exchange acceptance as no exchange" do
      habitation = build(:habitation, :broker_intake, aceita_permuta_answer: nil)

      expect(habitation.intake_missing_requirements(required_checks: %w[valor_negociacao])).not_to include("Aceita permuta")
      expect(habitation.intake_missing_requirements(required_checks: %w[permuta])).not_to include("Aceita permuta")
    end

    it "normalizes blank exchange acceptance to no before saving sale intakes" do
      habitation = build(:habitation, :broker_intake, aceita_permuta_answer: nil, aceita_permuta_flag: false)

      habitation.valid?

      expect(habitation.aceita_permuta_answer).to eq("nao")
      expect(habitation.aceita_permuta_flag).to be(false)
    end

    it "checks parking type and box only when those operational checks are active" do
      habitation = build(
        :habitation,
        :broker_intake,
        categoria: "Apartamento",
        tipo_vaga: nil,
        vagas_qtd: 1,
        numero_box: nil
      )

      missing = habitation.intake_missing_requirements(required_checks: %w[vagas tipo_vaga box])

      expect(missing).not_to include("Vaga de garagem")
      expect(missing).to include("Tipo de vaga", "Box")
    end

    it "does not require situation and occupation for land even when checks are active" do
      habitation = build(:habitation, :broker_intake, categoria: "Terreno", situacao: nil, ocupacao_status: nil)

      missing = habitation.intake_missing_requirements(required_checks: %w[situacao ocupacao])

      expect(missing).not_to include("Situação", "Ocupação")
    end
  end

  describe "#capture_price_reductions" do
    it "stores previous sale price and promotional value when sale price decreases" do
      habitation = create(:habitation, valor_venda_cents: 1_000_000_00, valor_promocional_cents: nil)

      habitation.update!(valor_venda_cents: 900_000_00)

      expect(habitation).to have_attributes(
        valor_venda_anterior_cents: 1_000_000_00,
        valor_promocional_cents: 900_000_00
      )
    end

    it "stores previous rent price and promotional value when rent price decreases" do
      habitation = create(:habitation, valor_venda_cents: 0, valor_locacao_cents: 6_000_00, valor_promocional_cents: nil)

      habitation.update!(valor_locacao_cents: 5_500_00)

      expect(habitation).to have_attributes(
        valor_locacao_anterior_cents: 6_000_00,
        valor_promocional_cents: 5_500_00
      )
    end
  end

  describe "#taxes_included_indicator?" do
    it "only shows included taxes for rental properties" do
      rental = build(:habitation, valor_venda_cents: 0, valor_locacao_cents: 5_000_00, valor_condominio_cents: 1, valor_iptu_cents: 100)
      sale = build(:habitation, valor_venda_cents: 900_000_00, valor_locacao_cents: 0, valor_condominio_cents: 1, valor_iptu_cents: 100)

      expect(rental).to be_taxes_included_indicator
      expect(sale).not_to be_taxes_included_indicator
    end
  end

  describe "#public_area_m2" do
    it "returns only the private area" do
      habitation = build(:habitation, area_privativa_m2: 82, area_total_m2: 137)

      expect(habitation.public_area_m2).to eq(82)
      expect(habitation.card_data[:area]).to eq(82)
      expect(habitation.area_formatted).to eq("82 m²")
    end

    it "does not fall back to total area" do
      habitation = build(:habitation, area_privativa_m2: nil, area_total_m2: 137)

      expect(habitation.public_area_m2).to be_nil
      expect(habitation.card_data[:area]).to be_nil
      expect(habitation.area_formatted).to be_nil
    end
  end
end
