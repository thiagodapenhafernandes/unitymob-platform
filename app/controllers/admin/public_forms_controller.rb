class Admin::PublicFormsController < Admin::BaseController
  requires_permission :manage, :site_publico
  before_action :set_public_form, only: [:show, :edit, :update, :destroy]

  def index
    PublicForm.ensure_default_site_forms!(tenant: current_tenant)
    @public_forms = current_tenant.public_forms.ordered.includes(:fields).paginate(page: params[:page], per_page: 20)
    @submissions_count = current_tenant.public_form_submissions.count
  end

  def show
    @submissions = @public_form.submissions.recent.with_attached_files
    @submissions = @submissions.searching(params[:q]) if params[:q].present?
    @submissions = @submissions.within_period(params[:period]) if params[:period].present?
    @submissions = @submissions.paginate(page: params[:page], per_page: 5)
  end

  def new
    @public_form = PublicForm.build_sample(tenant: current_tenant)
  end

  def create
    # Autosave (JSON) só cria rascunho; com commit=1 (botão Salvar/Publicar do editor) vale o status escolhido.
    attrs = request.format.json? && !explicit_save? ? public_form_params.merge(status: "draft") : public_form_params
    @public_form = current_tenant.public_forms.new(attrs)

    if @public_form.save
      respond_to do |format|
        format.html { redirect_to admin_public_form_path(@public_form), notice: "Formulário criado com sucesso." }
        format.json { render json: autosave_payload(@public_form), status: :created }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { ok: false, errors: @public_form.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  # Renderiza o modal real (mesmo partial e CSS do site) com os dados ainda não salvos do builder.
  def preview
    @public_form = build_preview_form
    render layout: "public_form_preview"
  end

  def update
    attrs = public_form_params
    if request.format.json? && !explicit_save?
      # Autosave só grava em rascunho e nunca muda o status (publicar/inativar é explícito).
      unless @public_form.draft?
        return render json: { ok: false, errors: ["Só rascunhos salvam sozinhos. Clique em Salvar para aplicar."] }, status: :conflict
      end

      attrs = attrs.except(:status)
    end

    if @public_form.update(attrs)
      respond_to do |format|
        format.html { redirect_to admin_public_form_path(@public_form), notice: "Formulário atualizado com sucesso." }
        format.json { render json: autosave_payload(@public_form) }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { ok: false, errors: @public_form.errors.full_messages }, status: :unprocessable_entity }
      end
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

  # Salvamento explícito feito em segundo plano pelo editor (Salvar/Publicar sem sair): aplica qualquer status.
  def explicit_save?
    params[:commit].to_s == "1"
  end

  # Resposta do autosave do preview: onde salvar da próxima vez e o id de cada campo (pela posição).
  def autosave_payload(form)
    {
      ok: true,
      status: form.status,
      status_label: form.status_label,
      update_url: admin_public_form_path(form),
      edit_url: edit_admin_public_form_path(form),
      fields: form.fields.to_h { |field| [field.position.to_s, field.id] }
    }
  end

  def build_preview_form
    attrs = public_form_params.to_h
    field_rows = attrs.delete("fields_attributes").to_h.map { |key, row| row.merge("preview_key" => key) }
    form = current_tenant.public_forms.new(attrs)
    form.title = form.title.presence || "Título do formulário"
    form.subtitle = form.subtitle.presence || "Subtítulo do formulário"
    form.slug = form.slug.to_s.parameterize.presence || form.name.to_s.parameterize.presence || "preview"

    field_rows.reject { |row| row["_destroy"] == "1" || (row["label"].blank? && row["name"].blank?) }
              .sort_by { |row| row["position"].to_i }
              .each { |row| form.fields.build(row.except("id", "_destroy")) }
    form
  end

  def public_form_params
    params.require(:public_form).permit(
      :name, :slug, :category, :title, :subtitle, :submit_label, :success_message,
      :redirect_url, :active, :status, :modal_enabled, :webhook_url, :distribution_rule_id,
      :modal_layout, :modal_size,
      modal_config: {},
      fields_attributes: [
        :id, :field_type, :name, :label, :placeholder, :hint, :required,
        :position, :options_text, :_destroy,
        config: {}
      ]
    )
  end
end
