module Admin::CaptacoesHelper
  def captacao_feature_options(*groups)
    options = groups.flatten.compact_blank.map { |value| captacao_feature_label(value) }.compact_blank
    options.index_by { |label| captacao_feature_key(label) }.values.sort_by { |label| captacao_feature_key(label) }
  end

  def captacao_feature_selected?(selected_values, label)
    selected_keys = Array(selected_values).map { |value| captacao_feature_key(captacao_feature_label(value) || value) }
    selected_keys.include?(captacao_feature_key(label))
  end

  private

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
