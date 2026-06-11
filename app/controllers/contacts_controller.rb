class ContactsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create]
  
  def new
    # Página de contato (pode ser renderizada pelo HomeController#contato)
  end
  
  def create
    c2s_intent = contact_params[:interest_intent].presence || "ambos"
    c2s_queue = case c2s_intent
                when "vender" then "c2s_venda"
                when "locar" then "c2s_locacao"
                else "c2s_ambos"
                end

    # Enviar webhook
    WebhookService.send_form_data("contact_form", contact_params.to_h.merge(
      c2s_intent: c2s_intent,
      c2s_queue: c2s_queue
    ), request: request)
    
    # Aqui você pode adicionar lógica para enviar email, salvar no banco, etc.
    
    redirect_to root_path, notice: 'Mensagem enviada com sucesso! Entraremos em contato em breve.'
  end
  
  private
  
  def contact_params
    params.require(:contact).permit(:name, :email, :phone, :message, :subject, :interest_intent)
  end
end
