# Cartões de apresentação do atendimento WhatsApp.
# Corretor: CRUD apenas dos SEUS cartões pessoais. Template de SISTEMA (tenant):
# visível para todos, editável só pelo admin da conta (tenant_owner) e nunca
# excluível/desativável — garante que o seletor do inbox jamais fique vazio.
class Admin::PresentationCardsController < Admin::BaseController
  before_action -> { check_permission!(:view, :whatsapp_inbox) }
  before_action :set_card, only: [:edit, :update, :destroy]

  def index
    PresentationCard.ensure_system_default_for(current_tenant)
    @system_cards = PresentationCard.system_templates.where(tenant_id: current_tenant.id).ordered
    @cards = personal_cards.ordered
  end

  def new
    @card = personal_cards.new(active: true)
  end

  def create
    @card = personal_cards.new(card_params.merge(tenant: current_tenant, system: false))
    if @card.save
      redirect_to safe_return_path || admin_presentation_cards_path, notice: "Cartão \"#{@card.label}\" criado."
    else
      return redirect_to safe_return_path, alert: @card.errors.full_messages.to_sentence if safe_return_path

      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    permitted = @card.system? ? system_card_params : card_params
    if @card.update(permitted)
      redirect_to safe_return_path || admin_presentation_cards_path, notice: "Cartão \"#{@card.label}\" atualizado."
    else
      return redirect_to safe_return_path, alert: @card.errors.full_messages.to_sentence if safe_return_path

      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @card.system?
      redirect_to admin_presentation_cards_path, alert: "O template da empresa não pode ser excluído."
    else
      @card.destroy
      redirect_to safe_return_path || admin_presentation_cards_path, notice: "Cartão removido."
    end
  end

  private

  def personal_cards
    current_admin_user.presentation_cards.personal
  end

  def set_card
    @card = PresentationCard.where(tenant_id: current_tenant.id).find_by(id: params[:id])
    if @card.nil? || !@card.editable_by?(current_admin_user)
      redirect_to admin_presentation_cards_path, alert: "Cartão não encontrado ou sem permissão."
    end
  end

  def card_params
    params.require(:presentation_card).permit(:label, :greeting, :use_photo, :active)
  end

  # Volta para a tela de origem (modal no inbox/lead) — só paths internos.
  def safe_return_path
    value = params[:return_to].to_s
    return nil unless value.start_with?("/") && !value.start_with?("//")

    value
  end

  # Template de sistema: sempre ativo (sem :active) — nunca some do seletor.
  def system_card_params
    params.require(:presentation_card).permit(:label, :greeting, :use_photo)
  end
end
