module CommercialContractsHelper
  def commercial_contract_status_badge(proposal)
    tone = case proposal.effective_status
           when "accepted" then :green
           when "canceled", "expired" then :red
           when "otp_pending" then :amber
           when "viewed" then :blue
           else :gray
           end
    ax_badge(proposal.status_label, tone: tone, dot: true)
  end

  def commercial_contract_money(cents)
    number_to_currency(cents.to_i / 100.0, unit: "R$ ", separator: ",", delimiter: ".")
  end

  def commercial_contract_document(value)
    digits = value.to_s.gsub(/\D/, "")
    return value.to_s if digits.length != 14

    digits.gsub(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, "\\1.\\2.\\3/\\4-\\5")
  end
end
