module Admin
  class SchedulingIntegrationsController < Admin::BaseController
    before_action :authorize_view!
    before_action :authorize_manage!, only: %i[update block_day unblock_day]

    def show
      load_settings
    end

    def pending_property
      @habitation = pending_photo_habitations.find(params[:id])
    end

    def update
      Setting.set(
        "photography_schedule_url",
        scheduling_params[:photography_schedule_url].to_s.strip,
        "URL externa para agendamento de fotos na captação"
      )

      redirect_to admin_scheduling_integration_path, notice: "Configuração de agendamento salva com sucesso."
    end

    def block_day
      block = PhotographyScheduleBlock.new(block_day_params)
      block.created_by = current_admin_user

      if block.save
        redirect_to admin_scheduling_integration_path, notice: "Dia bloqueado na agenda de fotografia."
      else
        load_settings
        @block_day_error = block.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    def unblock_day
      PhotographyScheduleBlock.find(params[:id]).destroy
      redirect_to admin_scheduling_integration_path, notice: "Bloqueio removido da agenda."
    end

    private

    def authorize_view!
      return if can?(:view, :agenda_fotografia) || can?(:manage, :agenda_fotografia) || can?(:manage, :integracoes)

      check_permission!(:view, :agenda_fotografia)
    end

    def authorize_manage!
      return if can?(:manage, :agenda_fotografia) || can?(:manage, :integracoes)

      check_permission!(:manage, :agenda_fotografia)
    end

    def load_settings
      @photography_schedule_url = Setting.get("photography_schedule_url", "")
      @blocked_days = PhotographyScheduleBlock.order(date: :asc)
      @pending_photo_habitations = pending_photo_habitations
    end

    def scheduling_params
      params.require(:scheduling).permit(:photography_schedule_url)
    end

    def block_day_params
      params.require(:photography_schedule_block).permit(:date, :reason)
    end

    def pending_photo_habitations
      scheduled_ids = Habitation.broker_intakes.where(photo_flow_choice: "schedule").select(:id)
      without_photo_ids = Habitation
        .broker_intakes
        .left_joins(:photos_attachments)
        .where(active_storage_attachments: { id: nil })
        .select(:id)

      Habitation
        .where(id: scheduled_ids)
        .or(Habitation.where(id: without_photo_ids))
        .where.not(intake_status: "published")
        .includes(:admin_user)
        .order(Arel.sql("photo_session_requested_at ASC NULLS LAST"), created_at: :desc)
        .limit(80)
    end
  end
end
