class NormalizeHabitationCommercialStatuses < ActiveRecord::Migration[7.1]
  STATUS_NORMALIZATION_MAP = {
    "venda" => "Venda",
    "venda e aluguel" => "Venda",
    "venda aluguel" => "Venda",
    "a venda" => "Venda",
    "para venda" => "Venda",
    "aluguel" => "Aluguel",
    "locacao" => "Aluguel",
    "locacao anual" => "Aluguel",
    "para alugar" => "Aluguel",
    "diaria" => "Diária",
    "temporada" => "Diária",
    "pendente" => "Pendente",
    "lancamento" => "Lançamento",
    "suspenso" => "Suspenso",
    "alugado imobiliaria" => "Alugado imobiliária",
    "alugado terceiros" => "Alugado terceiros",
    "vendido imobiliaria" => "Vendido imobiliária",
    "vendido terceiros" => "Vendido terceiros"
  }.freeze

  STATUS_KEYWORD_NORMALIZATION = [
    [/\b(?:diaria|temporada)\b/, "Diária"],
    [/\bpendente\b/, "Pendente"],
    [/\blancamento\b/, "Lançamento"],
    [/\bsuspenso\b/, "Suspenso"],
    [/\balugado\b.*\bimobiliaria\b|\bimobiliaria\b.*\balugado\b/, "Alugado imobiliária"],
    [/\balugado\b.*\bterceiros\b|\bterceiros\b.*\balugado\b/, "Alugado terceiros"],
    [/\balugado\b/, "Alugado terceiros"],
    [/\bvendido\b.*\bimobiliaria\b|\bimobiliaria\b.*\bvendido\b/, "Vendido imobiliária"],
    [/\bvendido\b.*\bterceiros\b|\bterceiros\b.*\bvendido\b/, "Vendido terceiros"],
    [/\bvendido\b/, "Vendido terceiros"],
    [/\b(?:aluguel|locacao|alugar)\b/, "Aluguel"],
    [/\b(?:venda|vende|vender)\b/, "Venda"]
  ].freeze

  class MigrationHabitation < ActiveRecord::Base
    self.table_name = "habitations"
  end

  def up
    MigrationHabitation
      .where("NULLIF(TRIM(status), '') IS NOT NULL")
      .in_batches(of: 1_000) do |relation|
        relation.pluck(:id, :status, :valor_venda_cents, :valor_locacao_cents).each do |id, status, sale_cents, rent_cents|
          normalized = normalize_status(status, sale_cents, rent_cents)
          next if normalized.blank? || normalized == status

          MigrationHabitation.where(id: id).update_all(status: normalized, updated_at: Time.current)
        end
      end
  end

  def down
    # Irreversível: os valores antigos eram variações externas sem contrato interno.
  end

  private

  def normalize_status(value, sale_cents, rent_cents)
    raw = value.to_s.strip.squish
    key = I18n.transliterate(raw).downcase

    STATUS_NORMALIZATION_MAP[key] ||
      STATUS_KEYWORD_NORMALIZATION.find { |pattern, _status| key.match?(pattern) }&.last ||
      fallback_status(raw, sale_cents, rent_cents)
  end

  def fallback_status(raw, sale_cents, rent_cents)
    return "Aluguel" if rent_cents.to_i.positive? && !sale_cents.to_i.positive?
    return "Venda" if sale_cents.to_i.positive?

    raw
  end
end
