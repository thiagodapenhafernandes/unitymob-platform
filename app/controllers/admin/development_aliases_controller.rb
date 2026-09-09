module Admin
  class DevelopmentAliasesController < BaseController
    before_action :require_admin!

    def create
      if params[:development_id].blank? || params[:names].to_s.split(/[\n,;]+/).all?(&:blank?)
        return render_create_error("Selecione um empreendimento e informe ao menos um nome alternativo.")
      end

      development = current_tenant.habitations.where(tipo: "Empreendimento").find(params[:development_id])
      names = params[:names].to_s.split(/[\n,;]+/).map(&:squish).compact_blank.uniq.first(30)
      created = 0
      DevelopmentAlias.transaction do
        names.each do |name|
          record = DevelopmentAlias.find_or_initialize_by(
            tenant: current_tenant,
            development: development,
            normalized_name: DevelopmentAlias.normalize(name)
          )
          record.name = name
          created += 1 if record.new_record?
          record.save!
        end
      end
      respond_with_aliases("#{created} nome(s) alternativo(s) salvo(s).", reset_modal: true)
    rescue ActiveRecord::RecordInvalid => e
      render_create_error(e.record.errors.full_messages.to_sentence)
    end

    def destroy
      DevelopmentAlias.where(tenant: current_tenant).find(params[:id]).destroy!
      respond_with_aliases("Nome alternativo removido.")
    end

    private

    def developments
      current_tenant.habitations.where(tipo: "Empreendimento")
        .order(Arel.sql("COALESCE(nome_empreendimento, titulo_anuncio, codigo) ASC")).limit(500)
    end

    def respond_with_aliases(message, reset_modal: false)
      respond_to do |format|
        format.turbo_stream do
          aliases = DevelopmentAlias.where(tenant: current_tenant).includes(:development).order(:normalized_name)
          streams = [turbo_stream.replace("development-alias-list", partial: "admin/development_aliases/list", locals: { aliases: aliases, message: message })]
          if reset_modal
            streams << turbo_stream.replace("newDevelopmentAliasModal", partial: "admin/development_aliases/modal", locals: { developments: developments })
          end
          render turbo_stream: streams
        end
        format.html { redirect_to edit_admin_property_setting_path(anchor: "property-settings-ai-aliases"), notice: message, status: :see_other }
      end
    end

    def render_create_error(message)
      locals = { developments: developments, error: message, development_id: params[:development_id], names: params[:names] }
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("development-alias-form", partial: "admin/development_aliases/form", locals: locals), status: :unprocessable_entity
        end
        format.html do
          @alias_form_locals = locals
          render :new, status: :unprocessable_entity
        end
      end
    end
  end
end
