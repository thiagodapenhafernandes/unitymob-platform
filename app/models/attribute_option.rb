class AttributeOption < ApplicationRecord
  include TenantScoped

  CONTEXTS = %w[habitation lead].freeze
  CATEGORIES = %w[feature infrastructure unique_feature source status imediacoes sale_reason].freeze

  before_validation :normalize_fields
  after_update_commit :sync_usage_on_rename, if: :saved_change_to_name?
  before_destroy :sync_usage_on_delete

  validates :name, :category, :context, presence: true
  validates :context, inclusion: { in: CONTEXTS }
  validates :category, inclusion: { in: CATEGORIES }
  validates :name, uniqueness: { scope: [:tenant_id, :category, :context], case_sensitive: false, message: "já existe nesta categoria" }
  validate :normalized_name_uniqueness
  validate :context_immutable, on: :update
  validate :category_immutable, on: :update

  scope :for_context, ->(context) { where(context: context) if context.present? }
  scope :for_category, ->(category) { where(category: category) if category.present? }
  scope :search_name, ->(query) { where("name ILIKE ?", "%#{query}%") if query.present? }
  scope :ordered, lambda {
    if column_names.include?("position")
      order(Arel.sql("position ASC NULLS LAST")).order(name: :asc)
    else
      order(name: :asc)
    end
  }

  before_create :assign_default_position

  private

  # Posiciona o novo registro no fim do seu grupo (context + category).
  def assign_default_position
    return unless self.class.column_names.include?("position")
    return if position.present?

    max = tenant.attribute_options.where(context: context, category: category).maximum(:position)
    self.position = (max || -1) + 1
  end

  def normalize_fields
    self.name = self.class.sanitize_name(name)
    self.context = context.to_s.strip
    self.category = category.to_s.strip
    self.name = AttributeOptions::HabitationFeatureNormalizer.label(name, category: category) if context == "habitation" && category.in?(%w[feature infrastructure])
  end

  def normalized_name_uniqueness
    return if tenant_id.blank? || context.blank? || category.blank? || name.blank?

    normalized_key = self.class.normalized_name_key(name)
    return if normalized_key.blank?

    duplicate = self.class
      .where(tenant_id: tenant_id, context: context, category: category)
      .where.not(id: id)
      .select(:id, :name)
      .find { |option| self.class.normalized_name_key(option.name) == normalized_key }

    errors.add(:name, "já existe nesta categoria") if duplicate && !errors.added?(:name, "já existe nesta categoria")
  end

  def self.sanitize_name(value)
    value.to_s
      .tr("_", " ")
      .squish
      .sub(/[[:space:]]*[\.,;:!?]+[[:space:]]*\z/, "")
  end

  def self.normalized_name_key(value)
    AttributeOptions::HabitationFeatureNormalizer.key(sanitize_name(value))
  end

  def context_immutable
    return unless will_save_change_to_context?
    errors.add(:context, "não pode ser alterado após a criação")
  end

  def category_immutable
    return unless will_save_change_to_category?
    errors.add(:category, "não pode ser alterada após a criação")
  end

  def sync_usage_on_rename
    AttributeOptions::SyncUsageService.new(
      context: context_before_last_save || context,
      category: category_before_last_save || category,
      old_name: name_before_last_save,
      new_name: name,
      action: :rename,
      tenant: tenant
    ).call
  end

  def sync_usage_on_delete
    AttributeOptions::SyncUsageService.new(
      context: context,
      category: category,
      old_name: name,
      action: :delete,
      tenant: tenant
    ).call
  end
end
