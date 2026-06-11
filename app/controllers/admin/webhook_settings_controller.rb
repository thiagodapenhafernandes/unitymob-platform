class Admin::WebhookSettingsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :integracoes) }
  before_action :set_webhook_setting, only: [:edit, :update, :destroy, :test]

  def index
    @webhook_settings = WebhookSetting.all.order(created_at: :desc)
    @lead_share_tracking_days = HabitationShareLink.expiration_days
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
  
  private
  
  def set_webhook_setting
    @webhook_setting = WebhookSetting.find(params[:id])
  end

  def webhook_params
    params.require(:webhook_setting).permit(:webhook_url, :whatsapp_webhook_url, :enabled, :lead_capture_enabled, :description)
  end
end
