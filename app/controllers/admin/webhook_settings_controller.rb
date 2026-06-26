class Admin::WebhookSettingsController < Admin::BaseController
  OUTBOUND_ACTIONS = %w[new create edit update destroy test share_tracking].freeze

  before_action :authorize_webhook_settings!
  before_action :set_webhook_setting, only: [:edit, :update, :destroy, :test]
  before_action :set_inbound_webhook_token, only: [:update_inbound_token, :regenerate_inbound_token]

  def index
    @can_manage_outbound_webhooks = current_admin_user&.can?(:manage, :integracoes)
    @active_tab = resolve_active_tab
    @inbound_webhook_token = InboundWebhookToken.for_user(current_admin_user)

    if @can_manage_outbound_webhooks
      @webhook_settings = WebhookSetting.all.order(created_at: :desc)
      @lead_share_tracking_days = HabitationShareLink.expiration_days
    else
      @webhook_settings = WebhookSetting.none
      @lead_share_tracking_days = HabitationShareLink.expiration_days
    end
  end

  def new
    @webhook_setting = WebhookSetting.new(enabled: true, lead_capture_enabled: true)
  end

  def create
    @webhook_setting = WebhookSetting.new(webhook_params)

    if @webhook_setting.save
      redirect_to admin_webhook_settings_path, notice: 'Webhook criado com sucesso!'
    else
      render :new
    end
  end

  def edit
  end
  
  def update
    if @webhook_setting.update(webhook_params)
      redirect_to admin_webhook_settings_path, notice: 'Configurações de webhook atualizadas com sucesso!'
    else
      render :edit
    end
  end
  
  def destroy
    @webhook_setting.destroy
    redirect_to admin_webhook_settings_path, notice: 'Webhook removido com sucesso!'
  end

  def test
    if @webhook_setting.test_webhook
      redirect_to admin_webhook_settings_path, notice: 'Webhook de teste enviado com sucesso!'
    else
      redirect_to admin_webhook_settings_path, alert: 'Falha ao enviar webhook de teste. Verifique a URL e tente novamente.'
    end
  end

  def share_tracking
    raw_days = params[:lead_share_tracking_days].presence || HabitationShareLink::DEFAULT_EXPIRATION_DAYS
    days = raw_days.to_i.clamp(
      HabitationShareLink::MIN_EXPIRATION_DAYS,
      HabitationShareLink::MAX_EXPIRATION_DAYS
    )

    Setting.set(
      HabitationShareLink::EXPIRATION_SETTING_KEY,
      days.to_s,
      "Dias de validade do cookie/link de compartilhamento de corretor"
    )

    redirect_to admin_webhook_settings_path, notice: "Validade do compartilhamento atualizada para #{days} dias."
  end

  def update_inbound_token
    if @inbound_webhook_token.update(inbound_webhook_token_params)
      redirect_to admin_webhook_settings_path(tab: "inbound"), notice: "Webhook de entrada atualizado para #{@inbound_webhook_token.admin_user.name}."
    else
      redirect_to admin_webhook_settings_path(tab: "inbound"), alert: @inbound_webhook_token.errors.full_messages.to_sentence
    end
  end

  def regenerate_inbound_token
    @inbound_webhook_token.regenerate!
    redirect_to admin_webhook_settings_path(tab: "inbound"), notice: "Token de entrada regenerado para #{@inbound_webhook_token.admin_user.name}."
  end
  
  private

  def authorize_webhook_settings!
    check_permission!(:manage, :integracoes)
  end

  def resolve_active_tab
    return "inbound" unless @can_manage_outbound_webhooks

    params[:tab].to_s == "inbound" ? "inbound" : "outbound"
  end
  
  def set_webhook_setting
    @webhook_setting = WebhookSetting.find(params[:id])
  end

  def set_inbound_webhook_token
    @inbound_webhook_token = InboundWebhookToken.find(params[:token_id])
    return if @inbound_webhook_token.admin_user_id == current_admin_user.id

    redirect_to admin_webhook_settings_path(tab: "inbound"), alert: "Você só pode gerenciar o seu próprio webhook de entrada."
  end

  def webhook_params
    params.require(:webhook_setting).permit(:webhook_url, :whatsapp_webhook_url, :enabled, :lead_capture_enabled, :description)
  end

  def inbound_webhook_token_params
    params.require(:inbound_webhook_token).permit(:enabled)
  end
end
