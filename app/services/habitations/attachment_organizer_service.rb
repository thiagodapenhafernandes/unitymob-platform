# frozen_string_literal: true

module Habitations
  # Move attachments do ActiveStorage para um path organizado no DO Spaces:
  # imoveis/{codigo}/{folder}/{filename-sanitizado}-{shortid}.{ext}
  #
  # Por padrão o ActiveStorage gera keys hash na raiz do bucket. Esse serviço
  # roda após o save, detecta blobs ainda na key padrão e faz copy + delete + update key.
  #
  # Usado pelo Habitation para fichas_cadastro e autorizacoes_venda.
  class AttachmentOrganizerService
    # Mapeia o nome da associação ActiveStorage para a subpasta no bucket.
    FOLDER_MAP = {
      "fichas_cadastro"    => "fichas-cadastro",
      "autorizacoes_venda" => "autorizacoes"
    }.freeze

    def initialize(habitation)
      @habitation = habitation
    end

    def call
      return unless @habitation.codigo.present?

      FOLDER_MAP.each do |association, folder|
        next unless @habitation.respond_to?(association)
        next unless @habitation.public_send(association).attached?

        @habitation.public_send(association).attachments.each do |attachment|
          organize_attachment(attachment, folder)
        end
      end
    end

    private

    def organize_attachment(attachment, folder)
      blob = attachment.blob
      return if blob.nil?

      # Já está dentro da pasta organizada — nada a fazer (idempotente).
      expected_prefix = "imoveis/#{@habitation.codigo}/#{folder}/"
      return if blob.key.to_s.start_with?(expected_prefix)

      target_key = build_target_key(blob, folder)
      service = blob.service
      return unless service.respond_to?(:bucket)

      bucket = service.bucket # Aws::S3::Bucket
      source_object = bucket.object(blob.key)
      target_object = bucket.object(target_key)

      target_object.copy_from(source_object, metadata_directive: "COPY")
      source_object.delete

      blob.update_columns(key: target_key)
    rescue StandardError => e
      Rails.logger.error("[AttachmentOrganizerService] habitation=#{@habitation.codigo} blob=#{blob&.id} erro=#{e.class}: #{e.message}")
    end

    def build_target_key(blob, folder)
      original = blob.filename.to_s
      ext = File.extname(original)
      base = File.basename(original, ext).parameterize.presence || "arquivo"
      shortid = blob.key.to_s[0, 8].presence || SecureRandom.hex(4)
      "imoveis/#{@habitation.codigo}/#{folder}/#{base}-#{shortid}#{ext}"
    end
  end
end
