module Admin
  # Gerencia as colunas do funil de leads (AttributeOption context=lead/category=status):
  # reordenar, renomear, subtítulo, adicionar e remover. Renomear/remover delegam aos
  # callbacks do AttributeOption (AttributeOptions::SyncUsageService), que ajustam os
  # leads existentes.
  class LeadStatusesController < Admin::BaseController
    before_action -> { check_permission!(:manage, :catalogos) }

    def index
      render json: statuses_scope.map { |option|
        { id: option.id, name: option.name, description: option.description }
      }
    end

    def bulk_update
      rows = params.permit(statuses: [:id, :name, :description, :_destroy]).fetch(:statuses, [])

      AttributeOption.transaction do
        rows.each_with_index do |row, index|
          apply_row(row, index)
        end
      end

      # Persiste para o reload subsequente — o layout renderiza como toast.
      flash[:notice] = "Colunas do funil atualizadas."
      render json: { ok: true }
    rescue ActiveRecord::RecordInvalid => e
      message = e.record&.errors&.full_messages&.to_sentence
      render json: { ok: false, error: message.presence || e.message }, status: :unprocessable_entity
    end

    private

    def apply_row(row, index)
      id = row[:id].presence
      name = row[:name].to_s.strip
      description = row[:description].to_s.strip
      destroy = ActiveModel::Type::Boolean.new.cast(row[:_destroy])

      if id.present?
        option = current_tenant.attribute_options.find_by(id: id, context: "lead", category: "status")
        return if option.nil?

        if destroy
          option.destroy!
        else
          option.update!(name: name, description: description, position: index)
        end
      elsif !destroy && name.present?
        current_tenant.attribute_options.create!(
          context: "lead",
          category: "status",
          name: name,
          description: description,
          position: index
        )
      end
    end

    def statuses_scope
      current_tenant.attribute_options.where(context: "lead", category: "status").ordered
    end
  end
end
