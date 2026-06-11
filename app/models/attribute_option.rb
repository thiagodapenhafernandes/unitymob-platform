class AttributeOption < ApplicationRecord
  CONTEXTS = %w[habitation lead].freeze
  CATEGORIES = %w[feature infrastructure unique_feature source status imediacoes sale_reason].freeze

  before_validation :normalize_fields
  after_update_commit :sync_usage_on_rename, if: :saved_change_to_name?
  before_destroy :sync_usage_on_delete

  validates :name, :category, :context, presence: true
  validates :context, inclusion: { in: CONTEXTS }
  validates :category, inclusion: { in: CATEGORIES }
  validates :name, uniqueness: { scope: [:category, :context], case_sensitive: false, message: "já existe nesta categoria" }
  validate :context_immutable, on: :update
  validate :category_immutable, on: :update

  scope :for_context, ->(context) { where(context: context) if context.present? }
  scope :for_category, ->(category) { where(category: category) if category.present? }
  scope :search_name, ->(query) { where("name ILIKE ?", "%#{query}%") if query.present? }

  private

  def normalize_fields
    self.name = name.to_s.strip
    self.context = context.to_s.strip
    self.category = category.to_s.strip
    self.name = AttributeOptions::HabitationFeatureNormalizer.label(name, category: category) if context == "habitation" && category.in?(%w[feature infrastructure])
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
      action: :rename
    ).call
  end

  def sync_usage_on_delete
    AttributeOptions::SyncUsageService.new(
      context: context,
      category: category,
      old_name: name,
      action: :delete
    ).call
  end
end
