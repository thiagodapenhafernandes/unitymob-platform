# frozen_string_literal: true

module Admin
  class StoresController < Admin::BaseController
    before_action -> { check_permission!(:view, :lojas) }
    before_action -> { check_permission!(:manage, :lojas) }, only: %i[new create edit update destroy geocode]
    before_action :set_store, only: [:show, :edit, :update, :destroy]

    def index
      @stores = current_tenant.stores.includes(:director, :store_shifts).order(active: :desc, name: :asc)
      @stores = @stores.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
    end

    def show
    end

    def new
      @store = current_tenant.stores.new(
        timezone: "America/Sao_Paulo",
        geofence_radius_meters: 150,
        out_of_radius_tolerance_minutes: 10,
        auto_checkout_after_minutes: 60,
        active: true
      )
    end

    def create
      @store = current_tenant.stores.new(store_params)

      if @store.save
        redirect_to admin_store_path(@store), notice: "Loja cadastrada com sucesso."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      # Sem turno-fantasma auto-buildado: ele entrava sem admin_user e, agora que
      # store_shifts_attributes é permitido, era submetido e quebrava o save de
      # qualquer loja sem turnos (inclusive reativar arquivada). O botão "Adicionar
      # turno" do form cria a linha quando o admin quiser.
    end

    def update
      if @store.update(store_params)
        redirect_to admin_store_path(@store), notice: "Loja atualizada com sucesso."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      # Soft-delete: lojas operadas têm check_ins/manual_checkin_requests/regras
      # apontando via FK RESTRICT (sem ON DELETE), então um hard-delete estoura
      # ActiveRecord::InvalidForeignKey (500). Arquivar via active:false remove a
      # loja dos fluxos de check-in (Store.active/within_geofence_of/by_distance_from
      # e current_tenant.stores.active) preservando o histórico.
      if @store.update(active: false)
        redirect_to admin_stores_path, notice: "Loja arquivada."
      else
        redirect_to admin_store_path(@store), alert: "Não foi possível arquivar a loja."
      end
    end

    def geocode
      result = Geo::AddressGeocoder.new(
        address: params[:address],
        number: params[:number],
        neighborhood: params[:neighborhood],
        city: params[:city],
        state: params[:state],
        zip_code: params[:zip_code]
      ).call

      if result
        render json: {
          ok: true,
          lat: result.latitude,
          lng: result.longitude,
          display_name: result.display_name,
          house_number: result.house_number,
          provider: result.provider,
          precision: result.precision
        }
      else
        render json: { ok: false, error: "Endereço não localizado." }, status: :not_found
      end
    end

    private

    def set_store
      @store = current_tenant.stores.friendly.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      @store = current_tenant.stores.find(params[:id])
    end

    def store_params
      params.require(:store).permit(
        :name, :address, :number, :neighborhood, :zip_code, :city, :state, :phone, :creci,
        :latitude, :longitude,
        :geofence_radius_meters, :out_of_radius_tolerance_minutes,
        :auto_checkout_after_minutes, :timezone, :active,
        :director_admin_user_id, :footer_store_id,
        :turnos_config_manha_ativo,
        :turnos_config_manha_entrada_inicio,
        :turnos_config_manha_entrada_fim,
        :turnos_config_manha_pos_risca_inicio,
        :turnos_config_manha_pos_risca_fim,
        :turnos_config_manha_fora_roleta_inicio,
        :turnos_config_manha_fora_roleta_fim,
        :turnos_config_manha_checkout_delay_seconds,
        :turnos_config_manha_checkout_remove_from_queue,
        :turnos_config_tarde_ativo,
        :turnos_config_tarde_entrada_inicio,
        :turnos_config_tarde_entrada_fim,
        :turnos_config_tarde_pos_risca_inicio,
        :turnos_config_tarde_pos_risca_fim,
        :turnos_config_tarde_fora_roleta_inicio,
        :turnos_config_tarde_fora_roleta_fim,
        :turnos_config_tarde_checkout_delay_seconds,
        :turnos_config_tarde_checkout_remove_from_queue,
        :turnos_config_unico_ativo,
        :turnos_config_unico_entrada_inicio,
        :turnos_config_unico_entrada_fim,
        :turnos_config_unico_pos_risca_inicio,
        :turnos_config_unico_pos_risca_fim,
        :turnos_config_unico_fora_roleta_inicio,
        :turnos_config_unico_fora_roleta_fim,
        :turnos_config_unico_checkout_delay_seconds,
        :turnos_config_unico_checkout_remove_from_queue,
        store_shifts_attributes: [
          :id, :admin_user_id, :day_of_week, :start_time, :end_time, :active, :_destroy
        ]
      ).tap do |perms|
        turnos_config = build_turnos_config(perms)
        perms[:turnos_config] = turnos_config if Store.column_names.include?("turnos_config")
      end
    end

    def build_turnos_config(perms)
      boolean_type = ActiveModel::Type::Boolean.new
      base_config = @store&.operational_turnos_config || Store.default_turnos_config

      Store::OPERATIONAL_SHIFTS.each_with_object({}) do |shift, config|
        existing = base_config.fetch(shift, {})
        active = boolean_type.cast(perms.delete("turnos_config_#{shift}_ativo"))

        config[shift] = {
          "ativo" => active,
          "entrada" => {
            "inicio" => active ? config_param(perms, "turnos_config_#{shift}_entrada_inicio", existing.dig("entrada", "inicio")) : existing.dig("entrada", "inicio"),
            "fim" => active ? config_param(perms, "turnos_config_#{shift}_entrada_fim", existing.dig("entrada", "fim")) : existing.dig("entrada", "fim")
          },
          "pos_risca" => {
            "inicio" => active ? config_param(perms, "turnos_config_#{shift}_pos_risca_inicio", existing.dig("pos_risca", "inicio")) : existing.dig("pos_risca", "inicio"),
            "fim" => active ? config_param(perms, "turnos_config_#{shift}_pos_risca_fim", existing.dig("pos_risca", "fim")) : existing.dig("pos_risca", "fim")
          },
          "fora_roleta" => {
            "inicio" => active ? config_param(perms, "turnos_config_#{shift}_fora_roleta_inicio", existing.dig("fora_roleta", "inicio")) : existing.dig("fora_roleta", "inicio"),
            "fim" => active ? config_param(perms, "turnos_config_#{shift}_fora_roleta_fim", existing.dig("fora_roleta", "fim")) : existing.dig("fora_roleta", "fim")
          },
          "checkout" => {
            "delay_seconds" => active ? normalize_checkout_delay(config_param(perms, "turnos_config_#{shift}_checkout_delay_seconds", nil)) : existing.dig("checkout", "delay_seconds").to_i,
            "remove_from_queue" => active ? boolean_type.cast(perms.delete("turnos_config_#{shift}_checkout_remove_from_queue")) : boolean_type.cast(existing.dig("checkout", "remove_from_queue"))
          }
        }
        discard_turnos_config_params(perms, shift)
      end
    end

    def config_param(perms, key, fallback)
      perms.key?(key) ? perms.delete(key) : fallback
    end

    def discard_turnos_config_params(perms, shift)
      %w[
        entrada_inicio entrada_fim pos_risca_inicio pos_risca_fim
        fora_roleta_inicio fora_roleta_fim checkout_delay_seconds
        checkout_remove_from_queue
      ].each { |suffix| perms.delete("turnos_config_#{shift}_#{suffix}") }
    end

    def normalize_checkout_delay(value)
      return 0 if value.blank?

      raw = value.to_s.strip
      minutes = if raw.match?(/\A\d{1,2}:\d{2}\z/)
                  hours, mins = raw.split(":").map(&:to_i)
                  (hours * 60) + mins
                else
                  raw.to_i
                end
      [minutes, 0].max * 60
    end
  end
end
