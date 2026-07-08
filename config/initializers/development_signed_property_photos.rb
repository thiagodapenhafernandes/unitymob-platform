# frozen_string_literal: true

# =============================================================================
# SOMENTE DESENVOLVIMENTO — não afeta produção nem toca no DigitalOcean Spaces.
# =============================================================================
#
# Diagnóstico original: as fotos de imóvel eram objetos PRIVADOS no Spaces (o
# ACL só tinha FULL_CONTROL do dono, sem grant `public-read`). Nessa situação,
# o app renderizava a URL pública do CDN e o Spaces respondia 403 AccessDenied
# para acesso anônimo.
#
# Fallback local opcional: quando USE_DEVELOPMENT_SIGNED_PROPERTY_PHOTOS=true,
# development resolve fotos Active Storage para a URL assinada do Rails. O
# padrão agora é deixar o CDN aparecer também em development, porque o processo
# images:publish_public_habitation_photos publica os objetos com public-read.
#
# Produção continua intacta: o gate `Rails.env.development?` impede qualquer
# mudança de comportamento fora do ambiente local.
if Rails.env.development? && ENV["USE_DEVELOPMENT_SIGNED_PROPERTY_PHOTOS"].to_s.downcase.in?(%w[1 true yes])
  Rails.application.config.to_prepare do
    module DevSignedPropertyPhotoUrls
      # Fotos anexadas (Active Storage) → URL assinada do Rails em vez do CDN público.
      def cdn_url_for_attachment(attachment)
        return if attachment.blank?

        dev_signed_blob_path(attachment.respond_to?(:blob) ? attachment.blob : attachment)
      end

      def cdn_url_for_blob(blob)
        dev_signed_blob_path(blob)
      end

      private

      def dev_signed_blob_path(blob)
        return if blob.blank? || blob.try(:key).blank?

        Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
      rescue StandardError
        nil
      end
    end

    Storage::PublicCdnImageUrl.prepend(DevSignedPropertyPhotoUrls)
  end
end
