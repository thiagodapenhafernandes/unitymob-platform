# Um bloco de uma página do construtor (capa, texto, vitrine de imóveis, botão…). Os campos de cada
# tipo vivem em LandingPages::BlockTypes; `data` só guarda o que o tipo declara.
class LandingPageBlock < ApplicationRecord
  belongs_to :landing_page, inverse_of: :blocks
  belongs_to :tenant

  has_one_attached :image_desktop
  has_one_attached :image_mobile
  has_many_attached :item_images

  # Checkbox "remover imagem" do editor.
  attr_accessor :remove_image_desktop, :remove_image_mobile, :copy_images_from
  attr_reader :item_uploads

  def item_uploads=(uploads)
    @item_uploads = uploads
    @item_uploads_processed = false
    @uploaded_item_keys = []
  end

  validates :block_type, inclusion: { in: ->(_block) { LandingPages::BlockTypes.keys } }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :required_fields_for_type
  validate :same_tenant_as_page
  validate :valid_item_uploads

  # Bloco novo já nasce com os campos do tipo preenchidos (editor mostra o padrão certo).
  after_initialize :apply_type_defaults, if: :new_record?
  before_validation :assign_tenant_from_page
  before_validation :copy_block_images
  before_validation :assign_item_images
  before_validation :normalize_data
  before_save :capture_builder_uploads
  after_save :detach_removed_images
  after_commit :prepare_public_images
  after_commit :remove_unused_item_images

  scope :visible, -> { where(visible: true) }
  scope :ordered, -> { order(:position, :id) }

  def self.visible_composition(blocks)
    section_visible = true
    blocks.select do |block|
      section_visible = block.visible? if block.block_type == "section"
      section_visible && block.visible?
    end
  end

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

  def vimeo_id
    value(:url).to_s.match(%r{\Ahttps://(?:www\.)?(?:vimeo\.com/(?:video/)?|player\.vimeo\.com/video/)([0-9]+)(?:[/#?]|\z)})&.captures&.first
  end

  def video_embed_url
    if youtube_id
      "https://www.youtube-nocookie.com/embed/#{youtube_id}?rel=0"
    elsif vimeo_id
      # Unlisted Vimeo videos require the private hash; discard unrelated tracking/player parameters.
      url = URI.parse(value(:url))
      hash = URI.decode_www_form(url.query.to_s).to_h["h"] || url.path.split("/").last
      hash = nil unless hash.match?(/\A[a-f0-9]{6,32}\z/) && hash != vimeo_id
      "https://player.vimeo.com/video/#{vimeo_id}?dnt=1#{"&h=#{hash}" if hash}"
    end
  rescue URI::InvalidURIError, ArgumentError
    nil
  end

  # Endereço do iframe só se for https (nada de javascript:, data: ou http).
  def embed_url = value(:url).to_s.match?(%r{\Ahttps://[^\s"'<>]+\z}) ? value(:url).to_s : nil

  def public_form
    tenant&.public_forms&.active&.includes(:fields)&.find_by(id: value(:form_id)) if block_type == "form"
  end

  def item_image(item)
    @item_image_index ||= item_images.attachments.includes(:blob).index_by { |attachment| attachment.blob.metadata["landing_page_item_key"] }
    @item_image_index[item["image_key"]]
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

  def copy_block_images
    return unless new_record? && copy_images_from.present? && !@images_copied

    source = landing_page&.blocks&.find_by(id: copy_images_from)
    return errors.add(:base, "O bloco de origem deve pertencer a esta página") unless source

    @images_copied = true
    image_desktop.attach(source.image_desktop.blob) if source.image_desktop.attached?
    image_mobile.attach(source.image_mobile.blob) if source.image_mobile.attached?
    keys = Array(value(:items)).map { |item| item["image_key"] }.compact_blank
    source.item_images.attachments.includes(:blob).each do |attachment|
      item_images.attach(attachment.blob) if keys.include?(attachment.blob.metadata["landing_page_item_key"])
    end
  end

  def assign_item_images
    return if @item_uploads_processed || item_uploads.blank? || !LandingPages::BlockTypes::COLLECTIONS.key?(block_type)

    @item_uploads_processed = true
    rows = data.to_h["items"]
    rows = rows.values if rows.is_a?(Hash)
    Array(rows).first(50).each do |row|
      upload = item_uploads[row["row_key"].to_s]
      next unless upload.respond_to?(:tempfile)
      next unless valid_item_upload?(upload)

      key = SecureRandom.uuid
      row["image_key"] = key
      row["remove_image"] = false
      @uploaded_item_keys << key
      item_images.attach(io: upload.tempfile, filename: upload.original_filename, content_type: upload.content_type,
                         metadata: { landing_page_item_key: key })
    end
  end

  def valid_item_upload?(upload)
    upload.content_type.in?(%w[image/jpeg image/png image/webp]) && upload.size <= 20.megabytes
  end

  def valid_item_uploads
    return if item_uploads.blank?

    item_uploads.each_value do |upload|
      next unless upload.respond_to?(:tempfile)
      errors.add(:base, "Cada imagem deve ser JPG, PNG ou WebP e ter até 20 MB") unless valid_item_upload?(upload)
    end
  end

  def capture_builder_uploads
    profiles = case block_type
    when "cover" then { image_desktop: Storage::PublicImageVariants::BUILDER_COVER, image_mobile: Storage::PublicImageVariants::BUILDER_MOBILE }
    when "image" then { image_desktop: Storage::PublicImageVariants::BUILDER_CONTENT }
    when "video" then { image_desktop: Storage::PublicImageVariants::BUILDER }
    else {}
    end
    @builder_uploads = profiles.filter_map do |name, options|
      image = public_send(name)
      [image.blob, options] if attachment_changes[name.to_s] && image.attached?
    end
  end

  def prepare_public_images
    return if destroyed?

    Array(@builder_uploads).each { |blob, options| Storage::TransformVariantJob.perform_later(blob, options) }
    return if @uploaded_item_keys.blank?

    item_images.attachments.includes(:blob).each do |attachment|
      next unless @uploaded_item_keys.include?(attachment.blob.metadata["landing_page_item_key"])

      Storage::TransformVariantJob.perform_later(attachment.blob, Storage::PublicImageVariants::BUILDER)
    end
  end

  def remove_unused_item_images
    return if destroyed? || !LandingPages::BlockTypes::COLLECTIONS.key?(block_type)

    keys = Array(value(:items)).map { |item| item["image_key"] }.compact_blank
    item_images.attachments.includes(:blob).each do |attachment|
      attachment.purge_later unless keys.include?(attachment.blob.metadata["landing_page_item_key"])
    end
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
      errors.add(:base, "Informe um link válido do YouTube ou Vimeo (youtube.com/watch?v=…, youtu.be/… ou vimeo.com/…)") if value(:url).present? && video_embed_url.nil?
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
