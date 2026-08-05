class LeadMailer < ApplicationMailer

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.lead_mailer.new_lead_notification.subject
  #
  def new_lead_notification
    @lead = params[:lead]
    @property = lead_tenant.habitations.find_by(id: @lead.property_id)
    
    admin_email = ContactSetting.instance(tenant: lead_tenant).email_primary
    site_name = LayoutSetting.instance(tenant: lead_tenant).site_name.presence || lead_tenant.name
    
    mail(
      to: admin_email, 
      subject: "Novo Lead: #{@lead.name} - #{site_name}"
    )
  end

  def welcome_lead
    @lead = params[:lead]
    return if @lead.email.blank?

    @property = lead_tenant.habitations.find_by(id: @lead.property_id)
    admin_contact = ContactSetting.instance(tenant: lead_tenant)
    site_name = LayoutSetting.instance(tenant: lead_tenant).site_name.presence || lead_tenant.name

    mail(
      to: @lead.email,
      subject: "Recebemos seu contato! - #{site_name}",
      reply_to: admin_contact.email_primary
    )
  end

  # Aviso ao corretor recém-atribuído a um lead (disparado pela distribuição).
  def lead_assigned
    @lead = params[:lead]
    @corretor = params[:corretor]
    return if @corretor&.email.blank?

    @property = lead_tenant.habitations.find_by(id: @lead.property_id)
    # Motor único: mascara telefone/e-mail atrás de /s/:token quando ligado.
    @contact = Leads::ContactLinks.new(@lead, @corretor)

    mail(
      to: @corretor.notification_email,
      subject: "Novo lead atribuído a você: #{@lead.display_name}"
    )
  end

  private

  def lead_tenant
    @lead_tenant ||= @lead.tenant || Current.tenant || raise(ArgumentError, "Tenant obrigatório para e-mail de lead")
  end
end
