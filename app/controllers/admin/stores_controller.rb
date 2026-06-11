# frozen_string_literal: true

module Admin
  class StoresController < Admin::BaseController
    before_action :require_admin!, only: [:destroy]
    before_action :set_store, only: [:show, :edit, :update, :destroy]

    def index
      @stores = Store.includes(:director, :store_shifts).order(active: :desc, name: :asc)
      @stores = @stores.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
    end

    def show
    end

    def new
      @store = Store.new(
        timezone: "America/Sao_Paulo",
        geofence_radius_meters: 150,
        out_of_radius_tolerance_minutes: 10,
        auto_checkout_after_minutes: 60,
        active: true
      )
    end

    def create
      @store = Store.new(store_params)

      if @store.save
        redirect_to admin_store_path(@store), notice: "Loja cadastrada com sucesso."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @store.store_shifts.build(day_of_week: 1, start_time: "09:00", end_time: "18:00", active: true) if @store.store_shifts.empty?
    end

    def update
      if @store.update(store_params)
        redirect_to admin_store_path(@store), notice: "Loja atualizada com sucesso."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @store.destroy
      redirect_to admin_stores_path, notice: "Loja removida."
    end

    private

    def set_store
      @store = Store.friendly.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      @store = Store.find(params[:id])
    end

    def store_params
      params.require(:store).permit(
        :name, :address, :number, :neighborhood, :zip_code, :city, :state, :phone, :creci,
        :latitude, :longitude,
        :geofence_radius_meters, :out_of_radius_tolerance_minutes,
        :auto_checkout_after_minutes, :timezone, :active,
        :director_admin_user_id, :footer_store_id
      )
    end
  end
end
