class LeadMailer < ApplicationMailer

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.lead_mailer.new_lead_notification.subject
  #
  def new_lead_notification
    @lead = params[:lead]
    @property = Habitation.find_by(id: @lead.property_id)
    
    admin_email = ContactSetting.instance.email_primary
    
    mail(
      to: admin_email, 
      subject: "Novo Lead: #{@lead.name} - Salute Imóveis"
    )
  end

  def welcome_lead
    @lead = params[:lead]
    @property = Habitation.find_by(id: @lead.property_id)
    admin_contact = ContactSetting.instance

    mail(
      to: @lead.email,
      subject: "Recebemos seu contato! - Salute Imóveis",
      reply_to: admin_contact.email_primary
    )
  end

  # Aviso ao corretor recém-atribuído a um lead (disparado pela distribuição).
  def lead_assigned
    @lead = params[:lead]
    @corretor = params[:corretor]
    return if @corretor&.email.blank?

    @property = Habitation.find_by(id: @lead.property_id)
    # Motor único: mascara telefone/e-mail atrás de /s/:token quando ligado.
    @contact = Leads::ContactLinks.new(@lead, @corretor)

    mail(
      to: @corretor.email,
      subject: "Novo lead atribuído a você: #{@lead.display_name}"
    )
  end
end
