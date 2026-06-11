class Admin::AccessControlRulesController < Admin::BaseController
  before_action -> { check_permission!(:manage, :access_security) }
  before_action :set_rule, only: %i[update destroy]

  def create
    @rule = AccessControlRule.new(rule_params.merge(created_by: current_admin_user))

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
    @rule = AccessControlRule.find(params[:id])
  end

  def rule_params
    params.require(:access_control_rule).permit(:name, :rule_type, :scope_type, :profile_id, :admin_user_id, :ip_value, :enabled, :description)
  end
end
