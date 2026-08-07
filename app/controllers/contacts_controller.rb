class ContactsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create]
  
  def new
    # Página de contato (pode ser renderizada pelo HomeController#contato)
  end
  
  def create
    lead_intent = contact_params[:interest_intent].presence || "ambos"
    lead_queue = case lead_intent
                 when "vender" then "lead_venda"
                 when "locar" then "lead_locacao"
                 else "lead_ambos"
                 end

    payload = contact_params.to_h
    payload["phone"] = Phones::Normalizer.call(payload["phone"]).to_s if payload["phone"].present?

    # Enviar webhook
    WebhookService.send_form_data("contact_form", payload.merge(
      lead_intent: lead_intent,
      lead_queue: lead_queue
    ), request: request)
    
    # Aqui você pode adicionar lógica para enviar email, salvar no banco, etc.
    
    redirect_to root_path, notice: 'Mensagem enviada com sucesso! Entraremos em contato em breve.'
  end
  
  private
  
  def contact_params
    params.require(:contact).permit(:name, :email, :phone, :message, :subject, :interest_intent)
  end
end
