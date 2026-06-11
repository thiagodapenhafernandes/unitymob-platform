module Admin
  class ProfilesController < BaseController
    before_action :require_admin!
    before_action :set_profile, only: %i[show edit update destroy]

    def index
      @profiles = Profile.all.order(name: :asc)
    end

    def show
    end

    def new
      @profile = Profile.new(active: true, permissions: default_permissions)
    end

    def edit
    end

    def create
      @profile = Profile.new(profile_params)
      if @profile.save
        redirect_to edit_admin_profile_path(@profile), notice: "Perfil criado. Configure as permissões."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @profile.update(profile_params_with_permissions)
        redirect_to admin_profiles_path, notice: "Perfil e permissões atualizados."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @profile.admin_users.any?
        redirect_to admin_profiles_path, alert: "Não é possível excluir: há corretores vinculados a este perfil."
      else
        @profile.destroy
        redirect_to admin_profiles_path, notice: "Perfil excluído."
      end
    end

    private

    def set_profile
      @profile = Profile.find(params[:id])
    end

    def profile_params
      params.require(:profile).permit(:name, :active)
    end

    # Normaliza a entrada da matriz de checkboxes no permissions JSONB.
    # Estrutura esperada:
    #   params[:profile][:permissions][:admin] = "1" | "0"
    #   params[:profile][:permissions][:imoveis][:view] = "1"
    #   params[:profile][:permissions][:imoveis][:scope] = "own" | "all"
    def profile_params_with_permissions
      base = profile_params

      raw = params.dig(:profile, :permissions) || {}
      perms = {}

      perms["admin"] = truthy?(raw[:admin])

      Profile::RESOURCES.each do |res|
        key = res[:key]
        entry = raw[key] || {}
        res_perms = {}
        res[:actions].each do |action|
          res_perms[action] = truthy?(entry[action])
        end
        res_perms["scope"] = entry[:scope].presence_in(%w[own all]) if res[:scopeable]
        perms[key] = res_perms
      end

      base.merge(permissions: perms)
    end

    def truthy?(value)
      value.to_s.in?(%w[1 true on yes])
    end

    def default_permissions
      Profile.default_permissions_for("Corretor")
    end
  end
end
