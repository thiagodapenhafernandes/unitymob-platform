# frozen_string_literal: true

module DeviceRequest
  MOBILE_USER_AGENT = /Android|iPhone|iPod|iPad|IEMobile|Opera Mini/i

  private

  def mobile_device_request?
    request.user_agent.to_s.match?(MOBILE_USER_AGENT)
  end

  def desktop_device_request?
    !mobile_device_request?
  end
end
