namespace :enrich_attribute_options do
  desc "Migrate hardcoded Habitation constants to AttributeOption model"
  task perform: :environment do
    puts "Starting AttributeOption enrichment..."

    internal_features = if Habitation.respond_to?(:internal_features)
      Habitation.internal_features
    elsif Habitation.respond_to?(:const_defined?) && Habitation.const_defined?(:INTERNAL_FEATURES)
      Habitation::INTERNAL_FEATURES
    else
      []
    end

    external_features = if Habitation.respond_to?(:external_features)
      Habitation.external_features
    elsif Habitation.respond_to?(:const_defined?) && Habitation.const_defined?(:EXTERNAL_FEATURES)
      Habitation::EXTERNAL_FEATURES
    else
      []
    end

    # 1. Feature Categories (Internal)
    created_internal = 0
    skipped_internal = 0
    internal_features.each do |feature|
      if sync_attribute_option!(
        name: feature,
        category: 'feature',
        context: 'habitation'
      )
        created_internal += 1
      else
        skipped_internal += 1
      end
    end
    puts "--> Migrated #{created_internal} new Internal Features, skipped #{skipped_internal}."

    # 2. Infra/External Categories
    created_external = 0
    skipped_external = 0
    external_features.each do |infra|
      if sync_attribute_option!(
        name: infra,
        category: 'infrastructure',
        context: 'habitation'
      )
        created_external += 1
      else
        skipped_external += 1
      end
    end
    puts "--> Migrated #{created_external} new Infrastructure items, skipped #{skipped_external}."

    # 3. Unique Features (Badges) - Migrate from existing data
    # Since we just migrated to array, values might be empty or strings.
    # Safe approach: fetch all, flatten, uniq in Ruby (efficient enough for this dataset size)
    
    puts "fetching existing badges from database..."
    existing_badges = Habitation.pluck(:caracteristica_unica).flatten.compact.map(&:strip).reject(&:blank?).uniq
    
    defaults = ["Frente Mar", "Quadra Mar", "Decorado", "Mobiliado", "Vista Mar", "Lançamento", "Oportunidade", "Exclusividade"]
    all_badges = (existing_badges + defaults).uniq

    created_badges = 0
    skipped_badges = 0
    all_badges.each do |badge|
      if sync_attribute_option!(
        name: badge,
        category: 'unique_feature',
        context: 'habitation'
      )
        created_badges += 1
      else
        skipped_badges += 1
      end
    end
    puts "--> Migrated #{created_badges} new Unique Features (Badges), skipped #{skipped_badges}."

    puts "AttributeOption enrichment completed successfully!"
  end

  def sync_attribute_option!(name:, category:, context:)
    normalized_name = name.to_s.strip
    return false if normalized_name.blank?

    existing = AttributeOption.where(
      "LOWER(name) = ? AND category = ? AND context = ?",
      normalized_name.downcase,
      category,
      context
    ).exists?
    return false if existing

    option = AttributeOption.new(
      name: normalized_name,
      category: category,
      context: context
    )

    option.save
    option.persisted?
  rescue ActiveRecord::RecordInvalid => e
    if duplicate_record_error?(e)
      false
    else
      raise
    end
  end

  def duplicate_record_error?(exception)
    message = exception.message.to_s
    message.include?("já existe") || message.include?("already exists")
  end
end
