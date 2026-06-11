module Admin
  class AttributeOptionsController < Admin::BaseController
    before_action -> { check_permission!(:manage, :catalogos) }
    before_action :set_attribute_option, only: [:update, :destroy]

    def index
      # This action serves both the sidebar page (HTML) and modal usage (JSON)
      @options = AttributeOption.all

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
      @attribute_option = AttributeOption.new(attribute_option_params)

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
      @attribute_option.destroy

      return head :no_content if modal_request?

      respond_to do |format|
        format.html { redirect_to admin_attribute_options_path, notice: 'Atributo removido.' }
        format.json { head :no_content }
      end
    end

    private

    def set_attribute_option
      @attribute_option = AttributeOption.find(params[:id])
    end

    def attribute_option_params
      params.require(:attribute_option).permit(:name, :category, :context)
    end

    def modal_request?
      request.format.json? || request.xhr? || request.content_mime_type == Mime[:json]
    end
  end
end
