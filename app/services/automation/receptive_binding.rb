module Automation
  # Liga/desliga o início "clique em botão de template" como receptivo de um número de WhatsApp.
  # Reusa o runtime que já existe: cria (ou atualiza) o Fluxo de Resposta do template com TODOS os botões em
  # "Iniciar automação" apontando para este workflow, e aponta o número para esse fluxo. O caminho de cada
  # botão fica no builder. Nunca sobrescreve um Fluxo de Resposta que não seja deste workflow.
  class ReceptiveBinding
    class Error < StandardError; end

    def self.call(workflow, entry_config)
      new(workflow, entry_config).call
    end

    def initialize(workflow, entry_config)
      @workflow = workflow
      @config = entry_config.to_h.with_indifferent_access
    end

    def call
      receptive = config[:trigger].to_s == "whatsapp_flow_button" && ActiveModel::Type::Boolean.new.cast(config[:use_as_receptive])
      receptive ? bind : unbind
    end

    private

    attr_reader :workflow, :config

    def tenant = workflow.tenant

    def bind
      sender = tenant.whatsapp_sender_numbers.active.find_by(id: config[:whatsapp_sender_number_id]) or raise Error, "Escolha o número de WhatsApp do receptivo."
      template = tenant.whatsapp_templates.approved.find_by(id: config[:whatsapp_template_id]) or raise Error, "Escolha o template do receptivo."
      flow = tenant.whatsapp_response_flows.find_or_initialize_by(whatsapp_template_id: template.id)
      if flow.persisted? && flow.automation_workflow_id != workflow.id
        raise Error, "O template #{template.name} já tem o fluxo de resposta “#{flow.name}”. Edite-o em Fluxos de Resposta ou escolha outro template."
      end

      flow.assign_attributes(name: flow.name.presence || workflow.name.to_s.truncate(120), active: true, automation_workflow: workflow,
                             created_by: flow.created_by || workflow.created_by, button_actions: button_actions(template))
      flow.save!
      sender.update!(receptive_response_flow: flow)
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    def unbind
      tenant.whatsapp_response_flows.where(automation_workflow_id: workflow.id).find_each do |flow|
        flow.receptive_sender_numbers.update_all(receptive_response_flow_id: nil)
        flow.update!(active: false)
      end
    end

    def button_actions(template)
      template.interactive_buttons.select { |button| button["actionable_reply"] }.to_h do |button|
        [button["key"].to_s, { "button_key" => button["key"].to_s, "button_text" => button["text"].to_s, "action" => "run_automation", "automation_workflow_id" => workflow.id.to_s }]
      end
    end
  end
end
