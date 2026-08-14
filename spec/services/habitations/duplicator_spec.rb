require "rails_helper"

RSpec.describe Habitations::Duplicator do
  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = Tenant.default
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  let(:tenant) { Tenant.default }
  let(:actor) { create(:admin_user, :admin, tenant: tenant) }
  let(:broker) { create(:admin_user, tenant: tenant, name: "Captador Original") }

  def attach_text_file(record, association, filename)
    record.public_send(association).attach(
      io: StringIO.new("conteudo #{filename}"),
      filename: filename,
      content_type: "text/plain"
    )
  end

  it "cria uma cópia interna com novo código e sem publicação ou identidade de integração" do
    source = create(
      :habitation,
      tenant: tenant,
      codigo: "DUP-SRC-#{SecureRandom.hex(4)}",
      slug: "imovel-original",
      titulo_anuncio: "Apartamento original",
      status: "Venda",
      categoria: "Apartamento",
      nome_empreendimento: "Residencial Clone",
      bloco: "901",
      exibir_no_site_flag: true,
      exibir_no_site_portal_flag: true,
      publicar_chaves_na_mao: true,
      publicar_imovelweb: true,
      destaque_web_flag: true,
      codigo_dwv: "DWV-123",
      imovel_dwv: "Sim",
      vista_codigo: "VISTA-123",
      vista_payload: { "Codigo" => "123" },
      dwv_payload: { "codigo" => "DWV-123" },
      proprietario: "Dono Original",
      proprietario_celular: "(47) 99999-0000",
      proprietor: create(:proprietor, tenant: tenant, name: "Dono Original"),
      admin_user: broker,
      data_atualizacao_crm: 20.days.ago,
      preco_atualizado_em: 20.days.ago
    )
    source.address.update!(logradouro: "Rua Clone", numero: "10", complemento: "Apto 901")
    source.update!(descricao_web: "<p>Descricao rica original</p>", meta_description: "<p>Meta rica original</p>")
    source.broker_assignments.create!(admin_user: broker, role: :captador, commission_type: :percentage, commission_value: 2.5)
    attach_text_file(source, :photos, "foto.txt")
    attach_text_file(source, :fichas_cadastro, "ficha.txt")
    source.update!(photo_ids_order: [source.photos.attachments.first.id])

    result = described_class.new(
      source,
      actor: actor,
      tenant: tenant,
      copy_sensitive_data: true,
      copy_internal_documents: true
    ).call!

    duplicate = result.habitation.reload

    expect(duplicate).to be_persisted
    expect(duplicate.codigo).to be_present
    expect(duplicate.codigo).not_to eq(source.codigo)
    expect(duplicate.slug).not_to eq(source.slug)
    expect(duplicate.titulo_anuncio).to eq("Apartamento original")
    expect(duplicate.nome_empreendimento).to eq("Residencial Clone")
    expect(duplicate.bloco).to eq("901")
    expect(duplicate.exibir_no_site_flag).to be(false)
    expect(duplicate.exibir_no_site_portal_flag).to be(false)
    expect(duplicate.publicar_chaves_na_mao).to be(false)
    expect(duplicate.publicar_imovelweb).to be(false)
    expect(duplicate.destaque_web_flag).to be(false)
    expect(duplicate.codigo_dwv).to be_nil
    expect(duplicate.imovel_dwv).to be_nil
    expect(duplicate.vista_codigo).to be_nil
    expect(duplicate.vista_payload).to eq({})
    expect(duplicate.dwv_payload).to eq({})
    expect(duplicate.intake_origin).to be_nil
    expect(duplicate.intake_status).to eq("internal")
    expect(duplicate.preco_atualizado_em).to be_nil

    expect(duplicate.address.logradouro).to eq("Rua Clone")
    expect(duplicate.address.numero).to eq("10")
    expect(duplicate.proprietario).to eq("Dono Original")
    expect(duplicate.proprietario_celular).to eq("5547999990000")
    expect(duplicate.proprietor_id).to eq(source.proprietor_id)
    expect(duplicate.photos.attachments.size).to eq(1)
    expect(duplicate.fichas_cadastro.attachments.size).to eq(1)
    expect(duplicate.photo_ids_order).to eq([duplicate.photos.attachments.first.id])
    expect(duplicate.broker_assignments.size).to eq(1)
    expect(duplicate.broker_assignments.first.admin_user_id).to eq(broker.id)
    expect(duplicate.descricao_web.to_plain_text).to include("Descricao rica original")
    expect(duplicate.meta_description.to_plain_text).to include("Meta rica original")

    log = duplicate.habitation_audit_logs.recent.first
    expect(log.action).to eq("created")
    expect(log.metadata).to include(
      "duplicated_from_habitation_id" => source.id,
      "duplicated_from_codigo" => source.codigo
    )
  end

  it "não copia dados sensíveis nem documentos internos quando o operador não tem acesso" do
    source = create(
      :habitation,
      tenant: tenant,
      proprietario: "Dono Restrito",
      proprietario_celular: "(47) 98888-0000",
      proprietor: create(:proprietor, tenant: tenant, name: "Dono Restrito")
    )
    attach_text_file(source, :photos, "foto.txt")
    attach_text_file(source, :autorizacoes_venda, "autorizacao.txt")

    duplicate = described_class.new(
      source,
      actor: actor,
      tenant: tenant,
      copy_sensitive_data: false,
      copy_internal_documents: false
    ).call!.habitation.reload

    expect(duplicate.proprietario).to be_blank
    expect(duplicate.proprietario_celular).to be_blank
    expect(duplicate.proprietor_id).to be_nil
    expect(duplicate.photos.attachments.size).to eq(1)
    expect(duplicate.autorizacoes_venda.attachments).to be_empty
  end
end
