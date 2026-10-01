# Converte cada página antiga (filtros + texto SEO) em blocos: uma Vitrine de imóveis com os mesmos
# filtros e, se havia texto SEO, um bloco de Texto depois dela. Idempotente (só páginas sem blocos) e
# sem tocar nas colunas antigas (filter_params/content), que seguem como rede de segurança.
# `q`/`search` são descartados de propósito: a página antiga nunca os aplicava no site público, e
# manter o resultado idêntico é mais seguro do que passar a filtrar.
class BackfillLandingPageBlocks < ActiveRecord::Migration[7.1]
  FILTER_KEYS = %w[
    category city neighborhood development property_codes transaction_type min_bedrooms min_suites min_parking
    target_price min_area opportunity characteristics caracteristica_unica status
  ].freeze

  class MigrationPage < ApplicationRecord
    self.table_name = "landing_pages"
  end

  class MigrationBlock < ApplicationRecord
    self.table_name = "landing_page_blocks"
  end

  def up
    MigrationPage.where.not(id: MigrationBlock.select(:landing_page_id)).find_each do |page|
      filters = page.filter_params.to_h.slice(*FILTER_KEYS).reject { |_key, value| value.blank? || Array(value).all?(&:blank?) }
      filters = filters.transform_values { |value| value.is_a?(Array) ? value.compact_blank : value }

      create_block(page, "property_showcase", 0, { "filters" => filters, "per_page" => 12, "visitor_filters" => true, "show_count" => true })
      create_block(page, "text", 1, { "heading" => "Mais informações", "body" => page.content, "width" => "narrow" }) if page.content.present?
    end
  end

  def down
    # Só desfaz o que esta migração criou (páginas cujos blocos são exatamente a conversão); blocos
    # criados no editor ficam, porque desfazer apagaria trabalho.
    say "Rollback não remove blocos: podem ter sido editados no construtor."
  end

  private

  def create_block(page, type, position, data)
    MigrationBlock.create!(landing_page_id: page.id, tenant_id: page.tenant_id, block_type: type, position: position, visible: true, data: data)
  end
end
