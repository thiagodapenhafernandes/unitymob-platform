module Integrations
  module Portals
    class FeedsController < ApplicationController
      skip_before_action :load_layout_settings

      before_action :set_integration
      before_action :authenticate_feed_request!

      def show
        return render json: { error: "Portal desativado" }, status: :forbidden unless @integration.enabled?
        return render json: { error: "Formato não suportado para este portal" }, status: :not_acceptable if invalid_format_request?

        scope = Portal::EligibilityScope.new(@integration).eligible_scope.includes(:address)
        scope_last_update = scope.maximum(:updated_at)
        @integration.update_columns(last_feed_at: Time.current, updated_at: Time.current)

        return unless stale?(etag: [@portal, @integration.updated_at.to_i, scope_last_update&.to_i], last_modified: scope_last_update, public: false)

        render_feed(scope.limit(feed_limit))
      end

      private

      # O TOKEN identifica unicamente a integração/tenant (feed_token é único
      # global). Resolvemos a integração PELO TOKEN e só então validamos que o
      # portal da URL bate com o da integração. Assim cada URL/token serve
      # exclusivamente o catálogo de UM tenant — nunca o de todos.
      def set_integration
        @portal = params[:portal].to_s.downcase
        @feed_token = feed_token_param

        if @feed_token.blank?
          return render json: { error: "Não autorizado" }, status: :unauthorized
        end

        @integration = PortalIntegration.find_by(feed_token: @feed_token)

        if @integration.nil? || @integration.portal.to_s.downcase != @portal || !PortalIntegration::PORTALS.include?(@portal)
          render json: { error: "Não autorizado" }, status: :unauthorized
        end
      end

      def authenticate_feed_request!
        return if performed?

        configured = @integration&.feed_token.to_s

        if configured.blank? || @feed_token.blank? || !ActiveSupport::SecurityUtils.secure_compare(@feed_token.to_s, configured)
          render json: { error: "Não autorizado" }, status: :unauthorized
        end
      end

      def feed_token_param
        (request.headers["X-Portal-Token"].presence || params[:token]).to_s
      end

      def xml_request?
        @integration.feed_format == :xml
      end

      def invalid_format_request?
        requested_format = params[:format].to_s
        return false if requested_format.blank?

        expected = @integration.feed_format.to_s

        requested_format != expected
      end

      def feed_limit
        value = params[:limit].to_i
        return 1000 if value <= 0

        value.clamp(1, 5000)
      end

      def render_feed(habitations)
        case @integration.feed_strategy
        when "olx_xml"
          serializer = Portal::OlxXmlSerializer.new(habitations: habitations, integration: @integration)
          render xml: serializer.to_xml
        when "olx_json"
          serializer = Portal::OlxJsonSerializer.new(habitations: habitations, integration: @integration, portal: @portal)
          render json: serializer.as_json
        when "chaves_xml"
          serializer = Portal::ChavesXmlSerializer.new(habitations: habitations, integration: @integration)
          render xml: serializer.to_xml
        else
          serializer = Portal::VrsyncXmlSerializer.new(habitations: habitations, integration: @integration)
          render xml: serializer.to_xml
        end
      end
    end
  end
end
