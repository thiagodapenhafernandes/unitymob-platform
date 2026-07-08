class HabitationPhotoShare < ApplicationRecord
  DEFAULT_EXPIRATION_DAYS = 30

  belongs_to :habitation
  belongs_to :admin_user, optional: true

  validates :token, presence: true, uniqueness: true
  validates :photo_ids, presence: true

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  before_validation :ensure_token, on: :create
  before_validation :ensure_expires_at, on: :create

  # Cria um link público com as fotos (attachment ids) selecionadas.
  def self.create_for(habitation:, admin_user:, photo_ids:)
    ids = normalize_photo_ids(photo_ids)
    create!(habitation: habitation, admin_user: admin_user, photo_ids: ids)
  end

  def self.normalize_photo_ids(photo_ids)
    Array(photo_ids)
      .flat_map { |id| id.to_s.split(",") }
      .map { |id| id.to_s.strip }
      .select { |id| id.match?(/\A\d+\z/) }
      .map(&:to_i)
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
end
