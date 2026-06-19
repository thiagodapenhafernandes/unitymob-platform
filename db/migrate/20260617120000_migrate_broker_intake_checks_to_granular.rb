class MigrateBrokerIntakeChecksToGranular < ActiveRecord::Migration[7.1]
  # Mapa legado (8 blocos) -> validações granulares. Inline para a migração ficar
  # independente de mudanças futuras no modelo.
  LEGACY_MAP = {
    "proprietario" => %w[proprietario proprietario_cidade],
    "endereco" => %w[endereco empreendimento unidade],
    "caracteristicas" => %w[area vagas situacao ocupacao caracteristicas],
    "infraestrutura" => %w[infraestrutura],
    "negociacao" => %w[valor_negociacao financeiro condicoes_negociacao],
    "fotos" => %w[fotos autorizacao],
    "visitas" => %w[chaves visitas],
    "complemento" => %w[definicoes titulo titulo_categoria descricao]
  }.freeze

  # Só expande quando o conjunto ainda está no formato antigo (marcadores exclusivos).
  LEGACY_ONLY_KEYS = %w[negociacao complemento].freeze

  class MigrationPropertySetting < ActiveRecord::Base
    self.table_name = "property_settings"
  end

  def up
    MigrationPropertySetting.reset_column_information
    MigrationPropertySetting.find_each do |setting|
      stored = Array(setting.required_broker_intake_checks).map(&:to_s)
      next if stored.blank?
      next if (stored & LEGACY_ONLY_KEYS).empty? # já está granular

      granular = stored.flat_map { |key| LEGACY_MAP[key] || [key] }.uniq
      setting.update_columns(required_broker_intake_checks: granular)
    end
  end

  def down
    # Conversão de volta não é reversível com fidelidade (relação 1:N); no-op.
  end
end
