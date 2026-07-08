module Admin
  module System
    # Erros da aplicação (rastreador interno) — visão cross-tenant, exclusiva
    # do Admin do Sistema (mesmo gate do painel do sistema).
    class ErrorEventsController < Admin::BaseController
      before_action :require_system_admin!
      before_action :set_error_event, only: [:show, :resolve, :reopen]

      def index
        @storage_ready = ErrorEvent.storage_ready?
        @exception_class = params[:exception_class].presence
        @source = params[:source].presence_in(ErrorEvent::SOURCES)
        @tenant_id = params[:tenant_id].presence
        @status = params[:status].presence_in(%w[open resolved]) || "all"
        @tenants = Tenant.order(:name)
        @exception_classes = @storage_ready ? ErrorEvent.distinct.pluck(:exception_class).compact.sort : []

        @error_events = filtered_scope.paginate(page: params[:page], per_page: 50) if @storage_ready
      end

      def show; end

      def resolve
        @error_event.resolve!
        redirect_to admin_system_error_event_path(@error_event), notice: "Erro marcado como resolvido."
      end

      def reopen
        @error_event.reopen!
        redirect_to admin_system_error_event_path(@error_event), notice: "Erro reaberto."
      end

      private

      def set_error_event
        @error_event = ErrorEvent.find(params[:id])
      end

      def filtered_scope
        scope = ErrorEvent.recent.includes(:tenant)
        scope = scope.by_class(@exception_class) if @exception_class
        scope = scope.by_source(@source) if @source
        scope = scope.where(tenant_id: @tenant_id) if @tenant_id

        case @status
        when "open" then scope.unresolved
        when "resolved" then scope.resolved
        else scope
        end
      end
    end
  end
end
