class HabitationPhotoShare < ApplicationRecord
  DEFAULT_EXPIRATION_DAYS = 30

  belongs_to :habitation
  belongs_to :admin_user, optional: true

  validates :token, presence: true, uniqueness: true
  validate :at_least_one_photo_source

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  before_validation :ensure_token, on: :create
  before_validation :ensure_expires_at, on: :create

  # Cria um link público com fotos internas (attachment ids) e/ou fotos externas
  # já resolvidas a partir do próprio imóvel no backend.
  def self.create_for(habitation:, admin_user:, photo_ids:, picture_urls: [])
    ids = normalize_photo_ids(photo_ids)
    create!(
      habitation: habitation,
      admin_user: admin_user,
      photo_ids: ids,
      picture_urls: normalize_picture_urls(picture_urls)
    )
  end

  def self.normalize_photo_ids(photo_ids)
    Array(photo_ids)
      .flat_map { |id| id.to_s.split(",") }
      .map { |id| id.to_s.strip }
      .select { |id| id.match?(/\A\d+\z/) }
      .map(&:to_i)
      .uniq
  end

  def self.normalize_picture_urls(urls)
    Array(urls)
      .flat_map { |url| url.to_s.split(",") }
      .map(&:strip)
      .select { |url| url.match?(/\Ahttps?:\/\//i) }
      .uniq
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def valid_for_access?
    !expired?
  end

  # Anexos selecionados, na ordem em que foram compartilhados, restritos às fotos
  # que ainda pertencem ao imóvel (isolamento por tenant via habitation).
  def selected_attachments
    stored_ids = Array(photo_ids).map(&:to_i)
    attachments = habitation.photos.attachments.includes(:blob).where(id: stored_ids).index_by(&:id)
    stored_ids.filter_map { |id| attachments[id] }
  end

  def selected_image_urls
    attachment_urls = selected_attachments.filter_map do |attachment|
      Storage::PublicCdnImageUrl.resolve("attachment" => attachment)
    end

    attachment_urls + self.class.normalize_picture_urls(picture_urls)
  end

  def register_view!
    update_columns(last_viewed_at: Time.current, views_count: views_count.to_i + 1)
  end

  private

  def ensure_token
    return if token.present?

    self.token = loop do
      candidate = SecureRandom.urlsafe_base64(24).tr("lIO0", "sxyz")
      break candidate unless self.class.exists?(token: candidate)
    end
  end

  def ensure_expires_at
    self.expires_at ||= DEFAULT_EXPIRATION_DAYS.days.from_now
  end

  def at_least_one_photo_source
    return if Array(photo_ids).any? || Array(picture_urls).any?

    errors.add(:base, "Selecione ao menos uma foto")
  end
end
