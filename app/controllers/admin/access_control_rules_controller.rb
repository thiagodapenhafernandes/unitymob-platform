class Admin::AccessControlRulesController < Admin::BaseController
  before_action -> { check_permission!(:manage, :access_security) }
  before_action :set_rule, only: %i[update destroy]

  def create
    @rule = current_tenant.access_control_rules.new(rule_params.merge(created_by: current_admin_user))

    if @rule.rule_type == "block_ip" && @rule.matches_ip?(request.remote_ip)
      redirect_to admin_access_security_path, alert: "Você não pode bloquear o IP usado neste acesso."
    elsif @rule.save
      redirect_to admin_access_security_path, notice: "Regra de acesso criada."
    else
      redirect_to admin_access_security_path, alert: @rule.errors.full_messages.to_sentence
    end
  end

  def update
    if @rule.update(rule_params)
      redirect_to admin_access_security_path, notice: "Regra de acesso atualizada."
    else
      redirect_to admin_access_security_path, alert: @rule.errors.full_messages.to_sentence
    end
  end

  def destroy
    @rule.destroy
    redirect_to admin_access_security_path, notice: "Regra de acesso removida."
  end

  private

  def set_rule
    @rule = manageable_access_control_rules.find(params[:id])
  end

  def rule_params
    permitted = params.require(:access_control_rule).permit(:name, :rule_type, :scope_type, :profile_id, :admin_user_id, :ip_value, :enabled, :description)
    if tenant_owner?
      permitted.delete(:profile_id) if permitted[:profile_id].present? && current_tenant.profiles.where(id: permitted[:profile_id]).none?
      permitted.delete(:admin_user_id) if permitted[:admin_user_id].present? && current_tenant.admin_users.account_members.where(id: permitted[:admin_user_id]).none?
      return permitted
    end

    permitted[:scope_type] = "user"
    permitted.delete(:profile_id)
    permitted.delete(:admin_user_id) if permitted[:admin_user_id].blank? || !manageable_admin_user_ids.include?(permitted[:admin_user_id].to_i)
    permitted
  end

  def manageable_access_control_rules
    return current_tenant.access_control_rules if tenant_owner?

    current_tenant.access_control_rules.where(scope_type: "user", admin_user_id: manageable_admin_user_ids)
  end

  def manageable_admin_user_ids
    @manageable_admin_user_ids ||= accessible_owner_ids(:access_security) || []
  end
end
