# frozen_string_literal: true

# Liga/desliga toda a feature de check-in geolocalizado via Setting key-value.
# Default: desligado. Enquanto estiver off, todas as rotas /field, /api/v1/field
# e integrações com DistributorService respondem como se a feature não existisse.
#
# Uso:
#   class Field::BaseController < ApplicationController
#     include FieldFeatureGate
#     before_action :ensure_field_enabled!
#   end
module FieldFeatureGate
  extend ActiveSupport::Concern

  SETTING_KEY = "field_checkin_enabled"
  DISABLED_AGENT_IDS_KEY = "field_checkin_disabled_admin_user_ids"

  # Disponível tanto como módulo (FieldFeatureGate.field_checkin_enabled?) quanto
  # como class method no controller que includa (ex: Field::BaseController.field_checkin_enabled?).
  def self.field_checkin_enabled?
    Setting.get(SETTING_KEY, "false").to_s == "true"
  end

  def self.field_agent_allowed?(admin_user, tenant: Current.tenant)
    return false unless admin_user&.active?

    !disabled_agent_ids(tenant: tenant || admin_user.tenant).include?(admin_user.id)
  end

  def self.disabled_agent_ids(tenant: Current.tenant)
    Setting.get(DISABLED_AGENT_IDS_KEY, "", tenant: tenant).to_s
           .split(/[,\s]+/)
           .filter_map { |value| Integer(value, exception: false) }
           .uniq
  end

  def self.disable_agent!(admin_user, tenant: Current.tenant)
    ids = disabled_agent_ids(tenant: tenant || admin_user.tenant)
    ids << admin_user.id
    Setting.set(DISABLED_AGENT_IDS_KEY, ids.uniq.sort.join(","), tenant: tenant || admin_user.tenant)
  end

  def self.enable_agent!(admin_user, tenant: Current.tenant)
    ids = disabled_agent_ids(tenant: tenant || admin_user.tenant) - [admin_user.id]
    Setting.set(DISABLED_AGENT_IDS_KEY, ids.sort.join(","), tenant: tenant || admin_user.tenant)
  end

  class_methods do
    def field_checkin_enabled?
      FieldFeatureGate.field_checkin_enabled?
    end
  end

  private

  def ensure_field_enabled!
    return if FieldFeatureGate.field_checkin_enabled?

    if request.format.json?
      render json: { error: "feature_disabled" }, status: :not_found
    else
      render plain: "Not Found", status: :not_found
    end
  end
end
