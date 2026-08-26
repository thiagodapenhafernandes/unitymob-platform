# frozen_string_literal: true

module DeviceRequest
  MOBILE_USER_AGENT = /Android|iPhone|iPod|iPad|IEMobile|Opera Mini/i
  # Sufixo configurado em mobile/capacitor.config.json (appendUserAgent) —
  # identifica requisições vindas do app híbrido (não do PWA/navegador).
  NATIVE_APP_USER_AGENT = /UnitymobFieldApp/

  private

  def mobile_device_request?
    request.user_agent.to_s.match?(MOBILE_USER_AGENT)
  end

  def desktop_device_request?
    !mobile_device_request?
  end

  def native_app_request?
    request.user_agent.to_s.match?(NATIVE_APP_USER_AGENT)
  end
end
