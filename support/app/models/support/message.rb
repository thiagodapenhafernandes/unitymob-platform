class Support::Message < ActiveRecord::Base
  self.table_name = "support_messages"
  AUDIO_TYPES = %w[audio/mpeg audio/mp4 audio/x-m4a audio/ogg audio/wav audio/x-wav audio/webm].freeze
  TYPES = (%w[image/jpeg image/png image/webp application/pdf] + AUDIO_TYPES).freeze
  MAX_BYTES = 10.megabytes
  belongs_to :ticket, class_name: "Support::Ticket"
  has_many_attached :files, service: Rails.env.test? ? :test : :support_private
  before_validation { self.uid ||= SecureRandom.uuid }
  validates :uid, :author, presence: true
  validates :side, inclusion: { in: %w[requester support] }
  validates :body, length: { maximum: 20_000 }
  validate do
    errors.add(:body, "escreva uma mensagem ou anexe um arquivo") if body.blank? && files.empty?
    errors.add(:base, "Chamado resolvido; abra outro vinculado") if ticket&.resolved?
    errors.add(:files, "máximo de 5 arquivos por mensagem") if files.size > 5
    files.each do |file|
      errors.add(:files, "use imagens, PDF ou áudio (MP3, M4A, OGG, WAV ou WebM) de até 10 MB") unless TYPES.include?(file.blob.content_type) && file.blob.byte_size <= MAX_BYTES
    end
  end
end
