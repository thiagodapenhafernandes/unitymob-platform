class PagesController < ApplicationController
  def trabalhe_conosco
    @page_name = 'trabalhe_conosco'
    # Página "Trabalhe Conosco" / "Seja um Corretor Parceiro"
  end

  def parcerias
    @page_name = 'parcerias'
    @page_title = 'Salute Parcerias | Seja nosso corretor parceiro'
    @page_description = 'Seja um corretor parceiro da Salute Imóveis e tenha acesso a imóveis exclusivos, suporte especializado e mais oportunidades de negócio.'
  end
  
  def submit_trabalhe_conosco
    # Enviar webhook
    WebhookService.send_form_data('work_with_us_form', work_params.to_h, request: request)
    
    redirect_to trabalhe_conosco_path, notice: 'Currículo enviado com sucesso! Entraremos em contato em breve.'
  end

  def submit_parcerias
    WebhookService.send_form_data('partnership_form', partnership_params.to_h, request: request)

    redirect_to parcerias_path, notice: 'Solicitação enviada com sucesso! Nosso time de parcerias entrará em contato.'
  end

  def simulador
    # Página "Simule um Financiamento"
  end

  def links_uteis
  end

  def corporativos
    @page_name = 'corporativos'
  end
  
  def privacy_policy
    # Política de Privacidade
  end
  
  def terms_of_use
    # Termos de Uso
  end
  
  private
  
  def work_params
    params.permit(:name, :email, :phone, :message, :creci, :experience, :cv)
  end

  def partnership_params
    params.require(:partnership).permit(:name, :email, :phone, :property_description, :creci, :city, :state)
  end
end
