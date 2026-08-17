module Admin
  class AttributeOptionsController < Admin::BaseController
    before_action -> { check_permission!(:manage, :catalogos) }
    before_action :require_tenant_owner_for_address_catalog!, only: [:index, :create]
    before_action :require_tenant_owner_for_existing_address_catalog!, only: [:update, :destroy]
    before_action :set_attribute_option, only: [:update]

    def index
      # This action serves both the sidebar page (HTML) and modal usage (JSON)
      rebuild_address_catalog_from_usage_if_needed
      @options = current_tenant.attribute_options

      if modal_request?
        @options = @options.for_context(params[:context]).for_category(params[:category]).order(name: :asc)
      else
        @options = @options.search_name(params[:query]).for_context(params[:context]).for_category(params[:category])
        @options = @options.order(context: :asc, category: :asc, name: :asc)
                           .paginate(page: params[:page], per_page: 20)
      end

      return render json: @options if modal_request?

      respond_to do |format|
        format.html # Renders index.html.erb for sidebar management
        format.json { render json: @options }
      end
    end

    def create
      @attribute_option = current_tenant.attribute_options.new(attribute_option_params)

      if @attribute_option.save
        return render json: @attribute_option, status: :created if modal_request?

        respond_to do |format|
          format.html { redirect_to admin_attribute_options_path, notice: 'Atributo criado com sucesso.' }
          format.json { render json: @attribute_option, status: :created }
        end
      else
        return render json: @attribute_option.errors, status: :unprocessable_entity if modal_request?

        respond_to do |format|
          format.html { redirect_to admin_attribute_options_path, alert: "Erro: #{@attribute_option.errors.full_messages.join(', ')}" }
          format.json { render json: @attribute_option.errors, status: :unprocessable_entity }
        end
      end
    end

    def update
      if @attribute_option.update(attribute_option_params)
        return render json: @attribute_option if modal_request?

        respond_to do |format|
          format.html { redirect_to admin_attribute_options_path, notice: 'Atributo atualizado.' }
          format.json { render json: @attribute_option }
        end
      else
        return render json: @attribute_option.errors, status: :unprocessable_entity if modal_request?

        respond_to do |format|
          format.html { redirect_to admin_attribute_options_path, alert: 'Erro ao atualizar.' }
          format.json { render json: @attribute_option.errors, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @attribute_option = current_tenant.attribute_options.find_by(id: params[:id])
      unless @attribute_option
        return head :no_content if modal_request?

        return redirect_to admin_attribute_options_path, alert: 'Atributo não encontrado.'
      end

      if @attribute_option.destroy
        return head :no_content if modal_request?

        respond_to do |format|
          format.html { redirect_to admin_attribute_options_path, notice: 'Atributo removido.' }
          format.json { head :no_content }
        end
      else
        errors = @attribute_option.errors.full_messages.presence || ["Não foi possível remover o atributo."]
        return render json: { errors: errors }, status: :unprocessable_entity if modal_request?

        redirect_to admin_attribute_options_path, alert: errors.to_sentence
      end
    end

    private

    def set_attribute_option
      @attribute_option = current_tenant.attribute_options.find(params[:id])
    end

    def rebuild_address_catalog_from_usage_if_needed
      return unless modal_request?
      return unless habitation_address_catalog_category?(params[:category])
      return unless address_catalog_action_allowed?(params[:category])

      AttributeOptions::RebuildFromUsageService.new(
        tenant: current_tenant,
        categories: [params[:category]]
      ).call
    end

    def require_tenant_owner_for_address_catalog!
      return unless habitation_address_catalog_category?(params[:category] || params.dig(:attribute_option, :category))
      return if address_catalog_action_allowed?(params[:category] || params.dig(:attribute_option, :category))

      deny_address_catalog_access
    end

    def require_tenant_owner_for_existing_address_catalog!
      option = current_tenant.attribute_options.find_by(id: params[:id])
      return unless option && habitation_address_catalog_category?(option.category)
      return if address_catalog_action_allowed?(option.category)

      deny_address_catalog_access
    end

    def habitation_address_catalog_category?(category)
      address_catalog_action_key(category).present?
    end

    def address_catalog_action_allowed?(category)
      return true if current_admin_user&.tenant_owner?

      action_key = address_catalog_action_key(category)
      action_key.present? && !Habitations::FieldLockPolicy.for(current_admin_user).action_locked?(action_key)
    end

    def address_catalog_action_key(category)
      {
        "street_type" => "acao:gerenciar_tipos_endereco",
        "city" => "acao:gerenciar_cidades",
        "neighborhood" => "acao:gerenciar_bairros",
        "commercial_neighborhood" => "acao:gerenciar_bairros_comerciais",
        "imediacoes" => "acao:gerenciar_imediacoes"
      }[category.to_s]
    end

    def deny_address_catalog_access
      respond_to do |format|
        format.html { redirect_to admin_attribute_options_path, alert: "Apenas o dono da conta pode gerenciar opções de endereço." }
        format.json { render json: { error: "forbidden" }, status: :forbidden }
      end
    end

    def attribute_option_params
      params.require(:attribute_option).permit(:name, :category, :context)
    end

    def modal_request?
      request.format.json? || request.xhr? || request.content_mime_type == Mime[:json]
    end
  end
end
