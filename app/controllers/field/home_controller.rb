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

      # Stats rápidas do dia
      @my_leads_today       = Lead.where(admin_user_id: @admin_user.id, created_at: Date.current.beginning_of_day..).count
      @my_active_captacoes  = Habitation.broker_intakes
                                        .where(admin_user_id: @admin_user.id)
                                        .where(intake_status: [nil, "draft", "returned_to_broker"])
                                        .count
      @my_total_habitations = Habitation.where(admin_user_id: @admin_user.id).count
      @recent_my_leads      = Lead.where(admin_user_id: @admin_user.id).order(created_at: :desc).limit(3)
    end

    private

    def today_shifts_for(user)
      user.store_shifts
          .includes(:store)
          .where(active: true, day_of_week: Time.current.wday)
          .order(:start_time)
    end
  end
end
