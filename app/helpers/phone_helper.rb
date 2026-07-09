# frozen_string_literal: true

module PhoneHelper
  def format_phone(value)
    Phones::Normalizer.display(value).presence || value.to_s
  end
end
