# Um bloco de uma página do construtor (capa, texto, vitrine de imóveis, botão…). Os campos de cada
# tipo vivem em LandingPages::BlockTypes; `data` só guarda o que o tipo declara.
class LandingPageBlock < ApplicationRecord
  belongs_to :landing_page, inverse_of: :blocks
  belongs_to :tenant

  has_one_attached :image_desktop
  has_one_attached :image_mobile

  # Checkbox "remover imagem" do editor.
  attr_accessor :remove_image_desktop, :remove_image_mobile

  validates :block_type, inclusion: { in: ->(_block) { LandingPages::BlockTypes.keys } }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :required_fields_for_type
  validate :same_tenant_as_page

  # Bloco novo já nasce com os campos do tipo preenchidos (editor mostra o padrão certo).
  after_initialize :apply_type_defaults, if: :new_record?
  before_validation :assign_tenant_from_page
  before_validation :normalize_data
  after_save :detach_removed_images

  scope :visible, -> { where(visible: true) }
  scope :ordered, -> { order(:position, :id) }

  def definition = LandingPages::BlockTypes.find(block_type)

  def value(name) = data.to_h[name.to_s]

  # Vitrine com filtros do visitante e paginação (só uma por página).
  def interactive_showcase?
    block_type == "property_showcase" && visible? && value(:visitor_filters) == true
  end

  # Largura na linha de colunas: "full" ou 1..3 (nunca maior que as colunas da página).
  def span = value(:span).to_s == "full" ? nil : value(:span).to_i.clamp(1, 3)

  YOUTUBE_ID = %r{\A(?:https?://)?(?:www\.|m\.)?(?:youtube\.com/(?:watch\?(?:[^\s#]*&)?v=|embed/|shorts/|live/)|youtu\.be/|youtube-nocookie\.com/embed/)([A-Za-z0-9_-]{11})(?![A-Za-z0-9_-])}

  def youtube_id = value(:url).to_s.match(YOUTUBE_ID)&.captures&.first

  # Endereço do iframe só se for https (nada de javascript:, data: ou http).
  def embed_url = value(:url).to_s.match?(%r{\Ahttps://[^\s"'<>]+\z}) ? value(:url).to_s : nil

  def public_form
    tenant&.public_forms&.active&.includes(:fields)&.find_by(id: value(:form_id)) if block_type == "form"
  end

  def label = definition&.label || block_type.to_s.humanize

  private

  def apply_type_defaults
    self.data = definition.normalize(data) if definition
  end

  def detach_removed_images
    image_desktop.purge_later if ActiveModel::Type::Boolean.new.cast(remove_image_desktop) && !attachment_changes["image_desktop"]
    image_mobile.purge_later if ActiveModel::Type::Boolean.new.cast(remove_image_mobile) && !attachment_changes["image_mobile"]
  end

  def assign_tenant_from_page
    self.tenant_id ||= landing_page&.tenant_id
  end

  def normalize_data
    self.data = definition ? definition.normalize(data) : {}
  end

  def required_fields_for_type
    case block_type
    when "form"
      errors.add(:base, "Selecione um formulário publicado desta conta") unless public_form
    when "button"
      errors.add(:base, "O botão precisa de texto e de destino válido") if value(:label).blank? || value(:url).blank?
    when "video"
      errors.add(:base, "Informe um link válido do YouTube (youtube.com/watch?v=…, youtu.be/… ou /embed/…)") if value(:url).present? && youtube_id.nil?
    when "embed"
      errors.add(:base, "O endereço do conteúdo incorporado precisa começar com https://") if value(:url).present? && embed_url.nil?
    when "text"
      errors.add(:base, "O texto precisa de um título ou de um texto") if value(:heading).blank? && value(:body).blank?
    end
  end

  def same_tenant_as_page
    return if landing_page.blank? || tenant_id.blank? || landing_page.tenant_id == tenant_id

    errors.add(:landing_page, "deve pertencer à mesma conta")
  end
end
