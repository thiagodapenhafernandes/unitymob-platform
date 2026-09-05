class SupportLabelsController < ApplicationController
  before_action { head :forbidden unless current_staff.operator? }
  before_action { @ticket = Support::Ticket.find(params[:ticket_id]) }
  after_action -> { Support::DispatchJob.perform_later if response.successful? && action_name != 'index' }
  rescue_from ActiveRecord::RecordInvalid do |error|
    render json:{error:error.record.errors.full_messages.to_sentence},status: :unprocessable_entity
  end
  rescue_from ActiveRecord::RecordNotUnique do
    render json:{error:'Já existe uma etiqueta com esse nome.'},status: :unprocessable_entity
  end
  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end
  def index
    render json: catalog
  end
  def create
    SupportLabel.create!(label_params)
    render json: catalog
  end
  def update
    label=SupportLabel.find(params[:id])
    label.with_lock do
      old_name=label.name
      label.update!(label_params)
      rename_on_tickets(old_name,label.name) if old_name!=label.name
    end
    render json: catalog
  end
  def destroy
    label=SupportLabel.find(params[:id])
    label.with_lock do
      rename_on_tickets(label.name,nil)
      label.destroy!
    end
    render json: catalog
  end
  def apply
    label=SupportLabel.find(params[:id])
    label.with_lock do
      ticket=Support::Ticket.find(params[:ticket_id])
      ticket.with_lock do
        return render(json:{error:'Chamado encerrado; etiquetas não podem ser alteradas.'},status: :unprocessable_entity) if ticket.resolved?
        names=label_names(ticket)
        names.reject!{|name|name.casecmp?(label.name)}
        names << label.name if ActiveModel::Type::Boolean.new.cast(params[:applied])
        save_names(ticket,names)
      end
    end
    render json: catalog
  end
  private
  def label_params = params.require(:label).permit(:name,:color,:description)
  def label_names(ticket) = ticket.labels.to_s.split(',').map(&:strip).reject(&:blank?)
  def catalog
    names=label_names(@ticket).map(&:downcase)
    {labels:SupportLabel.order(:name).map{|label|{id:label.id,name:label.name,color:label.color,text_color:label.text_color,description:label.description,applied:names.include?(label.name.downcase)}},resolved:@ticket.resolved?}
  end
  def rename_on_tickets(old_name,new_name)
    Support::Ticket.where("EXISTS (SELECT 1 FROM unnest(string_to_array(labels, ',')) value WHERE lower(trim(value)) = ?)",old_name.downcase).find_each do |ticket|
      ticket.with_lock do
        names=label_names(ticket).map{|name|name.casecmp?(old_name) ? new_name : name}.compact.uniq
        save_names(ticket,names, catalog_change:true)
      end
    end
  end
  def save_names(ticket,names,catalog_change:false)
    value=names.join(', ')
    return if ticket.labels==value
    before=ticket.labels
    if catalog_change
      # Renomear/excluir no catálogo atualiza metadados, sem reabrir nem recalcular SLA.
      if value.length>300
        ticket.errors.add(:labels, 'excede o limite de 300 caracteres')
        raise ActiveRecord::RecordInvalid.new(ticket)
      end
      ticket.update_columns(labels:value,revision:ticket.revision+1,updated_at:Time.current)
    else
      ticket.update!(labels:value,revision:ticket.revision+1)
    end
    Support::Audit.create!(account_id:ticket.account_id,ticket_id:ticket.id,actor:"staff:#{current_staff.id}",action:'ticket_updated',details:{labels:[before,value]})
    Support::Exchange.enqueue(ticket)
  end
end
