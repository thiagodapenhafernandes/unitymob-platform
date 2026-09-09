class BlogArticle < ApplicationRecord
  include TenantScoped
  include PublicRootSlug

  has_rich_text :content
  has_one_attached :cover do |image|
    image.variant :blog_social, resize_to_fill: [1200, 630], format: :jpg, preprocessed: true
    image.variant :blog_card, resize_to_limit: [640, 420], format: :webp, preprocessed: true
    image.variant :blog_hero, resize_to_limit: [1600, 1000], format: :webp, preprocessed: true
  end
  has_many :blog_categorizations, dependent: :destroy
  has_many :blog_categories, through: :blog_categorizations

  enum :status, { draft: "draft", scheduled: "scheduled", published: "published", inactive: "inactive" }, validate: true
  before_validation :normalize_fields
  validates :title, presence: true, length: { maximum: 250 }
  validates :slug, presence: true, length: { maximum: 250 }, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }, uniqueness: { scope: :tenant_id }
  validates :excerpt, length: { maximum: 1000 }
  validates :meta_title, length: { maximum: 250 }
  validates :meta_description, length: { maximum: 500 }
  validates :content, :published_at, presence: true, if: :publication_enabled?
  validate :categories_belong_to_tenant
  validate :safe_blog_attachments
  validate :schedule_in_future

  scope :publicly_visible, -> { where(status: %w[published scheduled]).where("published_at <= ?", Time.current) }
  scope :recent, -> { order(published_at: :desc, id: :desc) }
  scope :matching, ->(query) { where("blog_articles.title ILIKE ?", "%#{sanitize_sql_like(query.to_s.strip)}%") if query.present? }

  def public_url(fallback_base_url: nil)
    "#{tenant.public_base_url(fallback_base_url: fallback_base_url)}/#{slug}"
  end

  def publicly_visible?
    persisted? && publication_enabled? && published_at.present? && published_at <= Time.current
  end

  STATUS_LABELS = { "draft" => "Rascunho", "scheduled" => "Agendado", "published" => "Publicado", "inactive" => "Inativo" }.freeze

  scope :with_publication_status, ->(value) {
    case value
    when "published" then publicly_visible
    when "scheduled" then where(status: %w[published scheduled]).where("published_at > ?", Time.current)
    when "draft", "inactive" then where(status: value)
    else all
    end
  }

  def publication_enabled?
    published? || scheduled?
  end

  def publication_status
    return status unless publication_enabled? && published_at.present?
    published_at.present? && published_at > Time.current ? "scheduled" : "published"
  end

  def reading_minutes
    [(content.to_plain_text.split.size / 220.0).ceil, 1].max
  end

  private

  def normalize_fields
    self.title = title.to_s.strip
    self.slug = (slug.presence || title).to_s.parameterize
    self.published_at ||= Time.current if published?
    self.status = "scheduled" if published? && published_at.present? && published_at > Time.current
  end

  def categories_belong_to_tenant
    errors.add(:blog_categories, "devem pertencer à mesma conta") if blog_categories.any? { |category| category.tenant_id != tenant_id }
    errors.add(:blog_categories, "selecione pelo menos uma categoria") if publication_enabled? && blog_categories.empty?
  end

  def schedule_in_future
    return unless scheduled? && (will_save_change_to_status? || will_save_change_to_published_at?)
    errors.add(:published_at, "deve estar no futuro para agendar") if published_at.present? && published_at <= Time.current
  end

  def safe_blog_attachments
    if cover.attached?
      blob = cover.blob
      unless Blog::Storage.owned?(blob, tenant_id) && Blog::Storage::IMAGE_TYPES.include?(blob.content_type)
        errors.add(:cover, "deve ser uma imagem desta conta armazenada no Spaces")
      end
    end
    return unless content.body

    if content.body.attachables.any? { |blob| !Blog::Storage.owned?(blob, tenant_id) }
      errors.add(:content, "contém anexos inválidos ou de outra conta")
    end
    if Nokogiri::HTML.fragment(content.body.to_html).css("img, iframe, video, audio, source").any?
      errors.add(:content, "insira imagens e anexos pelo editor para enviá-los ao Spaces")
    end
  end
end
