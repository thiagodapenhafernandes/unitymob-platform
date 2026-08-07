module Admin::CaptacoesHelper
  def captacao_identity_title(captacao)
    parts = [
      captacao_building_name(captacao),
      captacao_address_line(captacao),
      captacao_unit_label(captacao)
    ].compact_blank

    compact_parts = deduplicate_captacao_identity_parts(parts)
    code_fallback = captacao.codigo.present? ? "Imóvel #{captacao.codigo}" : nil

    compact_parts.join(" · ").presence ||
      code_fallback ||
      captacao.display_title.presence ||
      "Imóvel"
  end

  def captacao_identity_subtitle(captacao)
    [
      captacao.neighborhood.presence,
      captacao.city.presence
    ].compact_blank.join(" · ")
  end

  def captacao_feature_options(*groups)
    options = groups.flatten.compact_blank.map { |value| captacao_feature_label(value) }.compact_blank
    options.index_by { |label| captacao_feature_key(label) }.values.sort_by { |label| captacao_feature_key(label) }
  end

  def captacao_feature_selected?(selected_values, label)
    selected_keys = Array(selected_values).map { |value| captacao_feature_key(captacao_feature_label(value) || value) }
    selected_keys.include?(captacao_feature_key(label))
  end

  private

  def captacao_building_name(captacao)
    captacao.edificio_nome.presence ||
      if captacao.association(:empreendimento).loaded?
        captacao.empreendimento&.nome_empreendimento.presence ||
          captacao.empreendimento&.titulo_anuncio.presence
      end
  end

  def captacao_address_line(captacao)
    [captacao.street.presence, captacao.street_number.presence].compact_blank.join(", ").presence
  end

  def captacao_unit_label(captacao)
    unit = captacao.unidade_numero.to_s.squish.presence
    return if unit.blank?

    unit.match?(/\A(unidade|un\.|apto|apartamento|sala|loja|lote|quadra)\b/i) ? unit : "Unidade #{unit}"
  end

  def deduplicate_captacao_identity_parts(parts)
    parts.each_with_object([]) do |part, unique_parts|
      normalized = I18n.transliterate(part.to_s).squish.downcase
      next if normalized.blank?
      next if unique_parts.any? { |existing| I18n.transliterate(existing.to_s).squish.downcase == normalized }

      unique_parts << part
    end
  end

  def captacao_feature_label(value)
    raw = value.to_s.strip
    return if raw.blank?

    label = AttributeOptions::HabitationFeatureNormalizer.label(raw)
    return label if label.present? && label != raw.tr("_", " ").squish
    return if raw.match?(/\A[a-z0-9]+(?:_[a-z0-9]+)+\z/)

    raw.squish
  end

  def captacao_feature_key(value)
    AttributeOptions::HabitationFeatureNormalizer.key(value)
  end
end
