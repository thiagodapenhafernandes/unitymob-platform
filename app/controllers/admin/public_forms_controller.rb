class Admin::PublicFormsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_public_form, only: [:show, :edit, :update, :destroy]

  def index
    PublicForm.ensure_default_site_forms!(tenant: current_tenant)
    @public_forms = current_tenant.public_forms.ordered.includes(:fields).paginate(page: params[:page], per_page: 20)
    @submissions_count = current_tenant.public_form_submissions.count
  end

  def show
    @submissions = @public_form.submissions.recent.paginate(page: params[:page], per_page: 20)
  end

  def new
    @public_form = current_tenant.public_forms.new(active: true, modal_enabled: true, submit_label: "Enviar", success_message: "Mensagem enviada com sucesso.")
  end

  def create
    @public_form = current_tenant.public_forms.new(public_form_params)

    if @public_form.save
      redirect_to admin_public_form_path(@public_form), notice: "Formulário criado com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @public_form.update(public_form_params)
      redirect_to admin_public_form_path(@public_form), notice: "Formulário atualizado com sucesso."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @public_form.submissions.exists?
      redirect_to admin_public_forms_path, alert: "Este formulário possui submissões e não pode ser removido."
    else
      @public_form.destroy
      redirect_to admin_public_forms_path, notice: "Formulário removido com sucesso."
    end
  end

  private

  def set_public_form
    @public_form = current_tenant.public_forms.find_by!(slug: params[:id])
  end

  def public_form_params
    params.require(:public_form).permit(
      :name, :slug, :category, :title, :subtitle, :submit_label, :success_message,
      :redirect_url, :active, :modal_enabled,
      modal_config: {},
      fields_attributes: [
        :id, :field_type, :name, :label, :placeholder, :hint, :required,
        :position, :options_text, :_destroy,
        config: {}
      ]
    )
  end
end
