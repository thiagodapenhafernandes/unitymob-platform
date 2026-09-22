module Admin
  # Topo do site público: menu (ordem, visibilidade, rótulos e links próprios), botão de ação,
  # telefone e aparência. O conteúdo das páginas continua nas telas de Estrutura.
  class PublicHeadersController < BaseController
    requires_permission :manage, :site_publico
    before_action :set_records

    def edit
    end

    def update
      saved = HomeSetting.transaction do
        @home_setting.update(header_params) && @contact_setting.update(phone_params) || raise(ActiveRecord::Rollback)
      end

      if saved
        redirect_to edit_admin_public_header_path, notice: "Topo do site atualizado."
      else
        @contact_setting.errors.each { |error| @home_setting.errors.add(:base, error.full_message) }
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_records
      @home_setting = HomeSetting.instance(tenant: current_tenant)
      @contact_setting = ContactSetting.instance(tenant: current_tenant)
    end

    def header_params
      attributes = params.fetch(:home_setting, {}).permit(
        :header_cta_label, :header_cta_url, :public_header_css, *HomeSetting::HEADER_COLOR_FIELDS.keys, header_menu: {}
      )
      attributes[:header_menu] = PublicHeaderMenu.normalize(attributes[:header_menu].to_h) if params[:home_setting]&.key?(:header_menu)
      attributes
    end

    def phone_params
      params.fetch(:contact_setting, {}).permit(:show_phone_in_header)
    end
  end
end
