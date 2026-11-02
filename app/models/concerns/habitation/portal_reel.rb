module Habitation::PortalReel
  extend ActiveSupport::Concern

  MAX_BYTES = 80_000_000
  CONTENT_TYPES = %w[video/mp4 video/quicktime].freeze

  included do
    has_one_attached :portal_reel
    validate :portal_reel_file_is_supported, if: -> { attachment_changes.key?("portal_reel") }
  end

  def portal_reel_exportable?
    portal_reel.attached? && portal_reel_status == "Pronto para envio"
  end

  def portal_reel_status
    return unless portal_reel.attached?

    blob = portal_reel.blob
    return "Formato inválido: use MP4 ou MOV" unless CONTENT_TYPES.include?(blob.content_type) && blob.filename.extension.to_s.downcase.in?(%w[mp4 mov])
    return "Excede o limite de 80 MB" if blob.byte_size > MAX_BYTES
    return "Aguardando análise do vídeo" unless blob.analyzed?

    metadata = blob.metadata
    duration = metadata["duration"].to_f
    width = metadata["width"].to_f
    height = metadata["height"].to_f
    return "Duração deve ser de 10 a 60 segundos" unless duration.finite? && duration.between?(10, 60)
    return "Vídeo deve ser vertical (9:16)" unless width.positive? && height.positive? && (width / height - 9.0 / 16).abs < 0.001

    "Pronto para envio"
  end

  private

  def portal_reel_file_is_supported
    return unless portal_reel.attached?
    return if portal_reel_status.in?(["Aguardando análise do vídeo", "Pronto para envio"])

    errors.add(:portal_reel, portal_reel_status)
  end
end
