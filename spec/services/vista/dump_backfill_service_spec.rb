require "rails_helper"
require "tmpdir"

RSpec.describe Vista::DumpBackfillService do
  def write_insert(path, table, columns, rows)
    values = rows.map do |row|
      "(" + columns.map { |column| row.fetch(column, "").to_s.inspect }.join(",") + ")"
    end.join(",\n")

    File.write(path, "INSERT INTO `#{table}` (#{columns.map { |column| "`#{column}`" }.join(",")}) VALUES #{values};\n")
  end

  it "backfills existing dump habitations without using the Vista API" do
    Dir.mktmpdir do |dir|
      cadimo_columns = described_class::CADIMO_FIELDS
      cadcli_columns = described_class::CADCLI_FIELDS

      write_insert(
        File.join(dir, "CADIMO.sql"),
        "CADIMO",
        cadimo_columns,
        [
          {
            "CODIGO" => "9999",
            "CODIGO_C" => "123",
            "CODIGO_M" => "77",
            "CORRETORES_DO_IMOVEL" => "Maria Corretora",
            "ENDERECO_TIPO" => "Rua",
            "ENDERECO" => "1000",
            "NUM_ENDERECO" => "55",
            "COMP_ENDERECO" => "301",
            "BAIRRO" => "Centro",
            "BAIRRO_COMERCIAL" => "Centro",
            "CIDADE" => "Balneario Camboriu",
            "UF" => "SC",
            "CEP" => "88330-000",
            "AR_CONDICIONADO" => "Sim",
            "BANHO_SOCIAL" => "Sim",
            "PLAYGROUD" => "Sim",
            "TIPO_OFERTA_ZAP" => "Destaque",
            "MODELO_CASA_MINEIRA" => "simples",
            "AC_PERMUTA_VALOR" => "500000",
            "COMISSAO_CAPTADOR" => "0",
            "PERCENTUAL_COMISSAO" => "6",
            "COMISSAO_CORRETOR" => "1.5",
            "VLR_COMISSAO" => "0",
            "VLR_LIVRE_PROPRIETARIO" => "131",
            "OBS_VENDA" => "Tem Administração? Sim\nValor da comissão: 7500"
          }
        ]
      )

      write_insert(
        File.join(dir, "CADCLI.sql"),
        "CADCLI",
        cadcli_columns,
        [
          {
            "CODIGO_C" => "123",
            "NOME" => "Proprietário Teste",
            "CELULAR" => "47 99999-0000",
            "EMAIL_R" => "proprietario@example.com"
          }
        ]
      )

      broker = create(:admin_user, vista_id: "77")
      proprietor = create(:proprietor, vista_code: "123", mobile_phone: nil, email: nil)
      habitation = create(
        :habitation,
        codigo: "9999",
        proprietor: proprietor,
        proprietario_codigo: "123",
        last_sync_message: "Importado do dump Vista teste",
        caracteristicas: {},
        infra_estrutura: {}
      )

      result = described_class.new(dump_dir: dir, dry_run: false).call

      expect(result.failed).to eq(0)
      expect(result.updated).to eq(1)

      habitation.reload
      expect(habitation.address).to have_attributes(
        logradouro: "1000",
        numero: "55",
        bairro: "Centro",
        cidade: "Balneario Camboriu",
        uf: "SC"
      )
      expect(habitation.caracteristicas.keys).to include("Ar-condicionado", "Banheiro social")
      expect(habitation.infra_estrutura).to include("Playground")
      expect(habitation.publicar_zapimoveis).to be(true)
      expect(habitation.publicar_casa_mineira).to be(true)
      expect(habitation.valor_aceito_permuta_cents).to eq(50_000_000)
      expect(habitation.captador_commission_percentage).to eq(BigDecimal("6"))
      expect(habitation.broker_commission_percentage).to eq(BigDecimal("1.5"))
      expect(habitation.valor_comissao_cents).to eq(750_000)
      expect(habitation.valor_livre_proprietario_cents).to eq(13_100)
      expect(habitation.salute_rental_management_flag).to be(true)
      expect(habitation.proprietario_celular).to eq("47 99999-0000")
      expect(habitation.proprietario_email).to eq("proprietario@example.com")
      expect(habitation.corretor_nome).to eq("Maria Corretora")
      expect(habitation.admin_user_id).to eq(broker.id)

      expect(proprietor.reload.mobile_phone).to eq("47 99999-0000")
      expect(proprietor.email).to eq("proprietario@example.com")
    end
  end
end
