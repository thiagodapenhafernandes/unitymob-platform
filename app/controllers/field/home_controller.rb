# frozen_string_literal: true

module Field
  class HomeController < BaseController
    def show
      # Requests JSON caem aqui (cache antigo do SW apontando pra /field
      # com params lat/lng). Responde vazio pra evitar 406.
      if request.format.json?
        render json: { ok: true, redirect: field_root_path }
        return
      end

      @admin_user       = current_admin_user
      @default_store    = @admin_user.default_store
      @field_enabled    = FieldFeatureGate.field_checkin_enabled?
      @active_check_in  = @field_enabled ? @admin_user.active_check_in : nil
      @today_shifts     = @field_enabled ? today_shifts_for(@admin_user) : []

      lead_scope = current_tenant.leads.where(admin_user_id: @admin_user.id)
      intake_scope = current_tenant.habitations.broker_intakes.where(admin_user_id: @admin_user.id)
      habitation_scope = current_tenant.habitations.where(admin_user_id: @admin_user.id)

      @my_leads_today = lead_scope.where(created_at: Date.current.beginning_of_day..).count
      @new_leads_count = lead_scope.where(status: Lead.status_value(:novo)).count
      @waiting_leads_count = lead_scope.where(status: Lead.status_value(:waiting_acceptance)).count
      @in_service_leads_count = lead_scope.where(status: Lead.status_value(:em_atendimento)).count
      @pending_leads_count = @new_leads_count + @waiting_leads_count
      @stale_new_leads_count = lead_scope
                               .where(status: [Lead.status_value(:novo), Lead.status_value(:waiting_acceptance)])
                               .where("created_at < ?", 2.hours.ago)
                               .count

      @my_draft_captacoes = intake_scope.where(intake_status: [nil, "draft"]).count
      @my_returned_captacoes = intake_scope.where(intake_status: "returned_to_broker").count
      @my_active_captacoes = @my_draft_captacoes + @my_returned_captacoes
      @my_pending_review_captacoes = intake_scope.where(intake_status: Habitation::PENDING_REVIEW_INTAKE_STATUSES).count
      @my_total_habitations = habitation_scope.count
      @my_published_habitations = habitation_scope.where(exibir_no_site_flag: true).count

      @recent_my_leads = lead_scope.order(created_at: :desc).limit(5)
      @lead_properties_by_id = current_tenant.habitations.where(id: @recent_my_leads.filter_map(&:property_id).uniq).index_by(&:id)
      @recent_open_captacoes = intake_scope
                                .where(intake_status: [nil, "draft", "returned_to_broker"])
                                .order(updated_at: :desc)
                                .limit(3)
      @field_priorities = field_priorities
    end

    private

    def field_priorities
      items = []

      if @stale_new_leads_count.positive?
        items << {
          icon: "exclamation-circle",
          tone: "danger",
          title: "Leads sem contato",
          description: "#{@stale_new_leads_count} aguardando atendimento há mais de 2 horas",
          path: admin_leads_path(status: Lead.status_value(:novo))
        }
      end

      if @pending_leads_count.positive?
        items << {
          icon: "megaphone",
          tone: "warning",
          title: "Leads a atender",
          description: "#{@pending_leads_count} novo(s) ou aguardando aceite",
          path: admin_leads_path(status: Lead.status_value(:novo))
        }
      end

      if @my_returned_captacoes.positive?
        items << {
          icon: "arrow-counterclockwise",
          tone: "danger",
          title: "Captações devolvidas",
          description: "#{@my_returned_captacoes} precisam de ajuste antes de avançar",
          path: admin_captacoes_path(status: "returned_to_broker")
        }
      end

      if @my_draft_captacoes.positive?
        items << {
          icon: "journal-text",
          tone: "primary",
          title: "Captações em rascunho",
          description: "#{@my_draft_captacoes} cadastro(s) ainda incompleto(s)",
          path: admin_captacoes_path(status: "draft")
        }
      end

      items
    end

    def today_shifts_for(user)
      user.store_shifts
          .includes(:store)
          .where(active: true, day_of_week: Time.current.wday)
          .order(:start_time)
    end
  end
end
