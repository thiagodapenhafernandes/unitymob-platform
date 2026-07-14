class PagesController < ApplicationController
  before_action :load_public_identity

  def trabalhe_conosco
    @page_name = 'trabalhe_conosco'
    # Página "Trabalhe Conosco" / "Seja um Corretor Parceiro"
  end

  def parcerias
    @page_name = 'parcerias'
    @page_title = "#{@public_identity.name} | Seja nosso corretor parceiro"
    @page_description = "Seja um corretor parceiro da #{@public_identity.name} e tenha acesso a imóveis, suporte especializado e novas oportunidades de negócio."
  end
  
  def submit_trabalhe_conosco
    payload = work_params.to_h
    payload["phone"] = Phones::Normalizer.call(payload["phone"]).to_s if payload["phone"].present?

    # Enviar webhook
    WebhookService.send_form_data('work_with_us_form', payload, request: request)
    
    redirect_to trabalhe_conosco_path, notice: 'Currículo enviado com sucesso! Entraremos em contato em breve.'
  end

  def submit_parcerias
    payload = partnership_params.to_h
    payload["phone"] = Phones::Normalizer.call(payload["phone"]).to_s if payload["phone"].present?

    WebhookService.send_form_data('partnership_form', payload, request: request)

    redirect_to parcerias_path, notice: 'Solicitação enviada com sucesso! Nosso time de parcerias entrará em contato.'
  end

  def simulador
    # Página "Simule um Financiamento"
  end

  def links_uteis
    @useful_links = PublicSiteProfile.current(tenant: public_tenant).useful_link_options
  end

  def corporativos
    @page_name = 'corporativos'
  end
  
  def privacy_policy
    @public_site_profile = PublicSiteProfile.current(tenant: public_tenant)
    @public_identity = Tenants::PublicIdentity.new(public_tenant)
  end
  
  def terms_of_use
    @public_site_profile = PublicSiteProfile.current(tenant: public_tenant)
    @public_identity = Tenants::PublicIdentity.new(public_tenant)
  end
  
  private

  def load_public_identity
    @public_identity = Tenants::PublicIdentity.new(public_tenant)
  end
  
  def work_params
    params.permit(:name, :email, :phone, :message, :creci, :experience, :cv)
  end

  def partnership_params
    params.require(:partnership).permit(:name, :email, :phone, :property_description, :creci, :city, :state)
  end
end
