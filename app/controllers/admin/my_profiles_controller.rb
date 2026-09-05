class Admin::MyProfilesController < Admin::BaseController
  before_action :load_profile

  def edit; end

  def update
    attributes = params.require(:admin_user).permit(:avatar, :password, :password_confirmation)
    changing_password = attributes[:password].present? || attributes[:password_confirmation].present?
    attributes = attributes.except(:password, :password_confirmation) unless changing_password
    if changing_password && !@profile.valid_password?(params[:current_password].to_s)
      @profile.errors.add(:base, "Senha atual incorreta.")
    end
    if (file = attributes[:avatar]).present?
      unless file.respond_to?(:content_type) && file.content_type.in?(%w[image/jpeg image/png image/webp]) && file.size <= 5.megabytes
        @profile.errors.add(:avatar, "deve ser JPG, PNG ou WebP de até 5 MB.")
      end
    end
    if @profile.errors.any?
      return render :edit, status: :unprocessable_entity
    end
    if @profile.update(attributes)
      bypass_sign_in(current_admin_user.reload) if changing_password
      redirect_to edit_admin_my_profile_path, notice: "Perfil atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def load_profile
    @profile = current_admin_user.login_identity
  end
end
