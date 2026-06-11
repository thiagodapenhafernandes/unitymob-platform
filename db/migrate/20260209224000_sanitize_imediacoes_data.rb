# frozen_string_literal: true

class SanitizeImediacoesData < ActiveRecord::Migration[7.1]
  class MigrationAddress < ActiveRecord::Base
    self.table_name = "addresses"
  end

  class MigrationAttributeOption < ActiveRecord::Base
    self.table_name = "attribute_options"
  end

  INVALID_TOKENS = %w[me pz div n/a na s/n sn xxx teste test nil null].freeze

  def up
    say_with_time("Sanitizando dados de imediações (addresses + attribute_options)") do
      canonical_map = build_canonical_map
      sanitize_addresses!(canonical_map)
      sanitize_attribute_options!(canonical_map)
      ensure_attribute_options_cover_addresses!(canonical_map)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Migração de sanitização de dados não é reversível"
  end

  private

  def build_canonical_map
    candidates_by_key = Hash.new { |h, k| h[k] = [] }

    MigrationAttributeOption.where(context: "habitation", category: "imediacoes").pluck(:name).each do |raw|
      cleaned = clean_value(raw)
      next if invalid_value?(cleaned)

      candidates_by_key[normalized_key(cleaned)] << cleaned
    end

    MigrationAddress.where(addressable_type: "Habitation").pluck(:imediacoes).each do |raw_values|
      Array(raw_values).each do |raw|
        cleaned = clean_value(raw)
        next if invalid_value?(cleaned)

        candidates_by_key[normalized_key(cleaned)] << cleaned
      end
    end

    candidates_by_key.transform_values { |values| pick_canonical(values) }
  end

  def sanitize_addresses!(canonical_map)
    MigrationAddress.where(addressable_type: "Habitation").find_each do |address|
      current = Array(address.imediacoes)
      next if current.empty?

      cleaned = current.map { |value| map_to_canonical(value, canonical_map) }
                       .compact
                       .uniq

      next if cleaned == current

      address.update_columns(imediacoes: cleaned, updated_at: Time.current)
    end
  end

  def sanitize_attribute_options!(canonical_map)
    scope = MigrationAttributeOption.where(context: "habitation", category: "imediacoes")
    grouped = Hash.new { |h, k| h[k] = [] }

    scope.order(:id).find_each do |option|
      cleaned = clean_value(option.name)
      key = normalized_key(cleaned)

      if invalid_value?(cleaned) || !canonical_map.key?(key)
        option.delete
        next
      end

      grouped[key] << option
    end

    grouped.each do |key, options|
      canonical = canonical_map[key]
      keeper = options.shift

      # Remove duplicates from same logical key first
      options.each(&:delete)

      # If another row already has the canonical name, keep that one and remove current keeper
      existing_canonical = scope.where("lower(name) = lower(?)", canonical).where.not(id: keeper.id).order(:id).first
      if existing_canonical
        keeper.delete
        next
      end

      keeper.update_columns(name: canonical, updated_at: Time.current) if keeper.name != canonical
    end
  end

  def ensure_attribute_options_cover_addresses!(canonical_map)
    existing = MigrationAttributeOption.where(context: "habitation", category: "imediacoes")
                                       .pluck(:name)
                                       .map { |name| normalized_key(name) }
                                       .to_set

    canonical_map.each_value do |canonical|
      key = normalized_key(canonical)
      next if existing.include?(key)

      MigrationAttributeOption.create!(
        name: canonical,
        category: "imediacoes",
        context: "habitation",
        created_at: Time.current,
        updated_at: Time.current
      )
      existing << key
    end
  end

  def map_to_canonical(value, canonical_map)
    cleaned = clean_value(value)
    return nil if invalid_value?(cleaned)

    canonical_map[normalized_key(cleaned)] || cleaned
  end

  def clean_value(value)
    value.to_s
         .gsub(/[[:space:]]+/, " ")
         .gsub(/\A[\s,;:\-\/|]+|[\s,;:\-\/|]+\z/, "")
         .strip
  end

  def invalid_value?(value)
    return true if value.blank?

    token = normalized_key(value)
    return true if INVALID_TOKENS.include?(token)
    return true if value.match?(/\A\d+\z/)
    return true if value.length < 3

    false
  end

  def normalized_key(value)
    I18n.transliterate(value.to_s).downcase.strip.gsub(/\s+/, " ")
  end

  def pick_canonical(values)
    uniq_values = values.uniq

    best = uniq_values.max_by do |value|
      score = 0
      score += 2 if value.match?(/[À-ÿ]/)
      score += 1 unless value == value.upcase
      score += 1 if value.match?(/\A\p{Upper}/)
      score += [value.length, 40].min / 40.0
      score
    end

    best.sub(/\A\p{Lower}/) { |char| char.upcase }
  end
end
