class CommercialContractMailer < ApplicationMailer
  def otp
    @proposal = params[:proposal]
    @tenant = @proposal.tenant
    @code = params[:code]
    @acceptance_url = params[:acceptance_url]

    mail(
      to: @proposal.representative_email,
      subject: "Código de aceite da proposta #{@proposal.public_token}"
    )
  end
end
