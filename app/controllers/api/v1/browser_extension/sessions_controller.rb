module Api
  module V1
    module BrowserExtension
      class SessionsController < BaseController
        skip_before_action :authenticate_grant!, only: :create
        skip_around_action :with_tenant_context, only: :create

        def create
          verifier = params[:verifier].to_s
          extension_id = params[:extension_id].to_s
          unless verifier.match?(/\A[A-Za-z0-9_-]{43}\z/) && BrowserExtensionGrant.allowed_extension?(extension_id)
            return render json: { error: "invalid_request" }, status: :bad_request
          end
          candidate = BrowserExtensionGrant.find_signed(params[:login_token].to_s, purpose: :browser_extension_pairing)
          candidate = nil unless candidate && candidate.extension_id == extension_id && candidate.challenge_digest == BrowserExtensionGrant.digest(verifier)
          return render json: { state: "pending" }, status: :accepted unless candidate

          access = AccessControl::Policy.call(admin_user: candidate.admin_user, request: request, trusted_device: candidate.trusted_device)
          return render json: { error: "access_denied" }, status: :forbidden unless access.allowed?

          if params[:expected_tenant_id].present? &&
              (candidate.tenant_id.to_s != params[:expected_tenant_id].to_s ||
               candidate.admin_user.login_identity.email.to_s.strip.downcase != params[:expected_email].to_s.strip.downcase ||
               ENV['DISCOVERY_INSTANCE_ID'].to_s != params[:expected_instance_id].to_s || request.base_url != params[:issuer])
            return render json: { error: "account_mismatch" }, status: :forbidden
          end

          token = candidate.exchange!
          return render json: { error: "pairing_expired" }, status: :gone unless token

          render json: { token: token, expires_at: candidate.expires_at.iso8601, tenant_id: candidate.tenant_id.to_s,
            instance_id: ENV["DISCOVERY_INSTANCE_ID"], login_email: candidate.admin_user.login_identity.email.to_s.strip.downcase }
        end

        def show
          render json: {
            tenant: { id: grant.tenant_id, name: grant.tenant.name },
            user: { id: grant.admin_user_id, name: grant.admin_user.name },
            capabilities: grant.capabilities, expires_at: grant.expires_at.iso8601,
            terms: { version: BrowserExtensionGrant::TERMS_VERSION, digest: BrowserExtensionGrant.digest(BrowserExtensionGrant::TERMS_TEXT),
                     text: BrowserExtensionGrant::TERMS_TEXT, accepted: grant.terms_accepted? }
          }
        end

        def accept_terms
          unless params[:accepted] == true && params[:version] == BrowserExtensionGrant::TERMS_VERSION &&
              params[:digest] == BrowserExtensionGrant.digest(BrowserExtensionGrant::TERMS_TEXT)
            return render json: { error: "invalid_terms" }, status: :unprocessable_entity
          end
          grant.with_lock do
            return render json: { error: "unauthorized" }, status: :unauthorized unless grant.accessible?
            unless grant.terms_accepted?
              grant.update!(terms_accepted_at: Time.current, terms_version: BrowserExtensionGrant::TERMS_VERSION,
                terms_digest: BrowserExtensionGrant.digest(BrowserExtensionGrant::TERMS_TEXT))
            end
          end
          show
        end

        def destroy
          grant.update!(revoked_at: Time.current)
          head :no_content
        end
      end
    end
  end
end
