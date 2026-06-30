module AttributeOptions
  class SyncUsageService
    def initialize(context:, category:, old_name:, new_name: nil, action:, tenant: nil)
      @context = context
      @category = category
      @old_name = old_name.to_s.strip
      @new_name = new_name.to_s.strip
      @action = action.to_sym
      @tenant = tenant || Current.tenant
      raise ArgumentError, "Tenant obrigatório para sincronizar catálogo dinâmico" if @tenant.blank?
    end

    def call
      return if @old_name.blank?

      case [@context, @category]
      when ["lead", "source"] then sync_lead_sources
      when ["lead", "status"] then sync_lead_statuses
      when ["habitation", "feature"] then sync_habitation_features
      when ["habitation", "infrastructure"] then sync_habitation_infrastructure
      when ["habitation", "unique_feature"] then sync_habitation_unique_features
      when ["habitation", "imediacoes"] then sync_habitation_surroundings
      when ["habitation", "sale_reason"] then sync_habitation_sale_reasons
      end
    end

    private

    def rename?
      @action == :rename
    end

    def delete?
      @action == :delete
    end

    def sync_lead_sources
      if rename?
        return if @new_name.blank? || @new_name == @old_name
        lead_scope.where(origin: @old_name).update_all(origin: @new_name)
      elsif delete?
        lead_scope.where(origin: @old_name).update_all(origin: nil)
      end
    end

    def sync_lead_statuses
      if rename?
        return if @new_name.blank? || @new_name == @old_name
        lead_scope.where(status: @old_name).update_all(status: @new_name, updated_at: Time.current)
      elsif delete?
        fallback_status = @tenant.attribute_options.where(context: "lead", category: "status").where.not(name: @old_name).order(name: :asc).pick(:name) || Lead::DEFAULT_STATUS
        lead_scope.where(status: @old_name).update_all(status: fallback_status, updated_at: Time.current)
      end
    end

    def sync_habitation_features
      habitation_scope.find_each do |habitation|
        original = habitation.caracteristicas
        next unless original.is_a?(Hash) && original.present?

        changed = false
        updated = original.deep_dup

        if rename?
          next if @new_name.blank? || @new_name == @old_name

          if updated.key?(@old_name)
            updated.delete(@old_name)
            updated[@new_name] = @new_name
            changed = true
          end

          updated.each do |key, value|
            next unless value.to_s == @old_name
            updated[key] = @new_name
            changed = true
          end
        elsif delete?
          removed_key = updated.delete(@old_name)
          removed_values_count = updated.delete_if { |_k, v| v.to_s == @old_name }.size
          changed = removed_key.present? || removed_values_count.positive?
        end

        persist_habitation_changes(habitation, caracteristicas: updated) if changed
      end
    end

    def sync_habitation_infrastructure
      habitation_scope.find_each do |habitation|
        current = normalize_list(habitation.infra_estrutura)
        next if current.empty?

        updated =
          if rename?
            next if @new_name.blank? || @new_name == @old_name
            current.map { |item| item == @old_name ? @new_name : item }
          elsif delete?
            current.reject { |item| item == @old_name }
          end

        next if updated == current
        persist_habitation_changes(habitation, infra_estrutura: updated.uniq)
      end
    end

    def sync_habitation_unique_features
      habitation_scope.find_each do |habitation|
        current = normalize_unique_features(habitation.caracteristica_unica)
        next if current.empty?

        updated =
          if rename?
            next if @new_name.blank? || @new_name == @old_name
            current.map { |item| item == @old_name ? @new_name : item }
          elsif delete?
            current.reject { |item| item == @old_name }
          end

        next if updated == current

        value = if unique_features_array_column?
                  updated.uniq
                else
                  updated.uniq.join(",")
                end
        persist_habitation_changes(habitation, caracteristica_unica: value)
      end
    end

    def sync_habitation_surroundings
      Address.where(addressable_type: "Habitation", addressable_id: habitation_scope.select(:id)).find_each do |address|
        current = normalize_list(address.imediacoes)
        next if current.empty?

        updated =
          if rename?
            next if @new_name.blank? || @new_name == @old_name
            current.map { |item| item == @old_name ? @new_name : item }
          elsif delete?
            current.reject { |item| item == @old_name }
          end

        normalized = updated.uniq
        next if normalized == current

        address.update_columns(imediacoes: normalized, updated_at: Time.current)
      end
    end

    def sync_habitation_sale_reasons
      return unless Habitation.column_names.include?("motivo_venda")

      if rename?
        return if @new_name.blank? || @new_name == @old_name
        habitation_scope.where(motivo_venda: @old_name).update_all(motivo_venda: @new_name, updated_at: Time.current)
      elsif delete?
        habitation_scope.where(motivo_venda: @old_name).update_all(motivo_venda: nil, updated_at: Time.current)
      end
    end

    def lead_scope
      @tenant.leads
    end

    def habitation_scope
      @tenant.habitations
    end

    def unique_features_array_column?
      @unique_features_array_column ||= Habitation.columns_hash["caracteristica_unica"]&.array
    end

    def normalize_unique_features(raw)
      Array(raw).flatten.compact.map { |item| item.to_s.strip }.reject(&:blank?)
    end

    def normalize_list(raw)
      case raw
      when Array
        raw.map { |item| item.to_s.strip }.reject(&:blank?)
      when Hash
        raw.values.map { |item| item.to_s.strip }.reject(&:blank?)
      when String
        raw.split(",").map(&:strip).reject(&:blank?)
      else
        []
      end
    end

    def persist_habitation_changes(habitation, attrs)
      habitation.assign_attributes(attrs)
      habitation.save!(validate: false)
    end
  end
end
