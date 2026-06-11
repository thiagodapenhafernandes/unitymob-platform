class SanitizeHabitationFeatureOptions < ActiveRecord::Migration[7.1]
  class MigrationAttributeOption < ActiveRecord::Base
    self.table_name = "attribute_options"
  end

  class MigrationHabitation < ActiveRecord::Base
    self.table_name = "habitations"
  end

  def up
    sanitize_attribute_options("feature")
    sanitize_attribute_options("infrastructure")
    sanitize_habitation_values
  end

  def down
    # Data-only normalization is intentionally not reversible.
  end

  private

  def sanitize_attribute_options(category)
    scope = MigrationAttributeOption.where(context: "habitation", category: category)

    scope.to_a.group_by { |option| canonical_key(option.name, category) }.each_value do |options|
      canonical = canonical_label(options.first.name, category)
      keeper = options.find { |option| option.name == canonical } || options.first
      duplicate_ids = options.reject { |option| option.id == keeper.id }.map(&:id)

      MigrationAttributeOption.where(id: duplicate_ids).delete_all if duplicate_ids.any?
      next if keeper.name == canonical

      keeper.update_columns(name: canonical, updated_at: Time.current)
    end
  end

  def sanitize_habitation_values
    MigrationHabitation.find_each do |habitation|
      updates = {}
      normalized_features = normalize_feature_hash(habitation.caracteristicas)
      normalized_infrastructure = normalize_list(habitation.infra_estrutura, "infrastructure")

      updates[:caracteristicas] = normalized_features if normalized_features != habitation.caracteristicas
      updates[:infra_estrutura] = normalized_infrastructure if normalized_infrastructure != habitation.infra_estrutura

      habitation.update_columns(updates.merge(updated_at: Time.current)) if updates.any?
    end
  end

  def normalize_feature_hash(raw)
    items =
      case raw
      when Hash
        values = raw.values
        if values.all? { |value| boolean_like_value?(value) }
          raw.select { |_key, value| truthy_value?(value) }.keys
        else
          raw.map { |key, value| value.to_s.strip.presence || key.to_s.strip }
        end
      else
        raw
      end

    normalize_list(items, "feature").index_by(&:itself)
  end

  def normalize_list(raw, category)
    values =
      case raw
      when Array then raw
      when Hash then raw.values
      when String then raw.split(/[,\n;]+/)
      else Array(raw)
      end

    values
      .flatten
      .filter_map { |value| canonical_label(value, category) }
      .index_by { |value| canonical_key(value, category) }
      .values
  end

  def canonical_label(value, category)
    AttributeOptions::HabitationFeatureNormalizer.label(value, category: category)
  end

  def canonical_key(value, category)
    AttributeOptions::HabitationFeatureNormalizer.key(canonical_label(value, category))
  end

  def boolean_like_value?(value)
    [true, false, nil, 0, 1, "0", "1", "true", "false", "t", "f"].include?(value)
  end

  def truthy_value?(value)
    [true, 1, "1", "true", "t"].include?(value)
  end
end
