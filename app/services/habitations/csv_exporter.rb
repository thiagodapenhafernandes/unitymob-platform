module Habitations
  # Geração de linhas do CSV de imóveis — extraído do controller para ser reusável
  # pelo job assíncrono. NÃO depende de current_admin_user: o campo "proprietario" só
  # é incluído (sanitized_export_fields) para admin/administrativo, que veem todos os
  # proprietários — logo não há mascaramento por linha aqui.
  class CsvExporter
    FIELDS = {
      "codigo" => "Referencia",
      "categoria" => "Categoria",
      "logradouro" => "Endereco",
      "numero" => "Endereco Numero",
      "complemento" => "Endereco Complemento",
      "dormitorios_qtd" => "Dormitorio",
      "valor_venda" => "Valor venda",
      "valor_locacao" => "Valor Aluguel",
      "status" => "Status",
      "bairro" => "Bairro",
      "cidade" => "Cidade",
      "uf" => "UF",
      "cep" => "CEP",
      "suites_qtd" => "Suite",
      "banheiros_qtd" => "Banheiros",
      "vagas_qtd" => "Vagas",
      "valor_condominio" => "Condominio",
      "valor_iptu" => "IPTU",
      "area_privativa_m2" => "Area privativa m2",
      "area_total_m2" => "Area total m2",
      "valor_por_m2" => "Valor do M2",
      "corretor_nome" => "Corretor",
      "proprietario" => "Proprietario",
      "codigo_empreendimento" => "Cod empreendimento"
    }.freeze

    DEFAULT_FIELDS = %w[codigo categoria logradouro numero complemento dormitorios_qtd valor_venda valor_locacao].freeze

    def self.header_row(fields)
      Array(fields).map { |field| FIELDS[field] || field }
    end

    def self.row(habitation, fields)
      Array(fields).map { |field| cell(habitation, field) }
    end

    def self.cell(habitation, field)
      case field
      when "codigo" then habitation.codigo
      when "categoria" then habitation.categoria
      when "status" then habitation.status
      when "logradouro" then habitation.logradouro || habitation.endereco
      when "numero" then habitation.numero
      when "complemento" then habitation.complemento
      when "bairro" then habitation.bairro
      when "cidade" then habitation.cidade
      when "uf" then habitation.uf
      when "cep" then habitation.cep
      when "dormitorios_qtd" then habitation.dormitorios_qtd
      when "suites_qtd" then habitation.suites_qtd
      when "banheiros_qtd" then habitation.banheiros_qtd
      when "vagas_qtd" then habitation.vagas_qtd
      when "valor_venda" then habitation.valor_venda_formatted
      when "valor_locacao" then habitation.valor_locacao_formatted
      when "valor_condominio" then habitation.valor_condominio_formatted
      when "valor_iptu" then habitation.valor_iptu_formatted
      when "area_privativa_m2" then habitation.area_privativa_m2
      when "area_total_m2" then habitation.area_total_m2
      when "valor_por_m2" then habitation.valor_por_m2_formatted
      when "corretor_nome" then habitation.corretor_nome
      when "proprietario" then habitation.proprietario
      when "codigo_empreendimento" then habitation.codigo_empreendimento
      else habitation.public_send(field)
      end
    end
  end
end
