# frozen_string_literal: true

# Ícones dos PWAs (admin e campo) derivados do logo do cliente (Identidade e
# Marca). O variant é processado uma única vez pelo ActiveStorage e cacheado;
# sem logo (ou falha de processamento), cai nos ícones genéricos.
class PwaIconsController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  SIZES = [192, 512].freeze

  def show
    size = params[:size].to_i
    return head :not_found unless SIZES.include?(size)

    logo = LayoutSetting.instance.logo
    return redirect_to "/field-icons/icon-#{size}.png" unless logo.attached? && logo.variable?

    variant = logo.variant(resize_and_pad: [size, size, background: "#ffffff"], format: :png).processed
    response.headers["Cache-Control"] = "public, max-age=86400"
    send_data variant.download, type: "image/png", disposition: "inline", filename: "icon-#{size}.png"
  rescue StandardError
    redirect_to "/field-icons/icon-#{size}.png"
  end
end
