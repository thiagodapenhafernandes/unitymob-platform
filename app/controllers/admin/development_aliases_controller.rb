module Admin
  class DevelopmentAliasesController < BaseController
    before_action :require_admin!

    def create
      development = current_tenant.habitations.where(tipo: "Empreendimento").find(params.require(:development_id))
      names = params.require(:names).to_s.split(/[\n,;]+/).map(&:squish).compact_blank.uniq.first(30)
      raise ActionController::BadRequest, "Informe ao menos um alias." if names.empty?

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
      redirect_to edit_admin_property_setting_path(anchor: "property-settings-ai-search"), notice: "#{created} alias(es) de empreendimento salvo(s)."
    rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing, ActionController::BadRequest => e
      redirect_to edit_admin_property_setting_path(anchor: "property-settings-ai-search"), alert: e.message
    end

    def destroy
      DevelopmentAlias.where(tenant: current_tenant).find(params[:id]).destroy!
      redirect_to edit_admin_property_setting_path(anchor: "property-settings-ai-search"), notice: "Alias removido."
    end
  end
end
