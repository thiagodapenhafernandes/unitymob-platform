module Api
  module V1
    module BrowserExtension
      class ConversationAvatarsController < BaseController
        rescue_from ArgumentError, ActionController::ParameterMissing, MiniMagick::Error,
          with: -> { render json: { error: "invalid_fields" }, status: :unprocessable_entity }

        def create
          unless grant.terms_accepted? && grant.admin_user.can?(:manage, :whatsapp_inbox)
            return render json: { error: "permission_denied" }, status: :forbidden
          end

          attrs = params.permit(:contact_phone, :image)
          phone = Phones::Normalizer.call(attrs[:contact_phone].to_s.first(40))
          raise ArgumentError if phone.blank?
          conversation = grant.tenant.whatsapp_conversations.visible_to(grant.admin_user).find_by!(contact_phone: phone)
          if attrs[:image].nil?
            return render json: { refresh: !conversation.contact_avatar.attached? || conversation.contact_avatar.blob.created_at < 1.day.ago }
          end

          conversation.sync_contact_avatar!(attrs[:image])
          render json: { saved: true }
        end
      end
    end
  end
end
