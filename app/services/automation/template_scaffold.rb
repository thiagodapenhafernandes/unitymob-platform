module Automation
  # Pré-montagem de uma automação a partir de um template do WhatsApp: entrada "clique em botão" e um caminho por
  # botão de resposta rápida, cada um já com uma mensagem para o usuário continuar editando.
  class TemplateScaffold
    def self.call(template)
      new(template).definition
    end

    def initialize(template)
      @template = template
    end

    def definition
      nodes = [entry]
      edges = []
      buttons.each_with_index do |button, index|
        condition_id = "response_condition_#{index + 1}"
        action_id = "action_#{index + 1}"
        nodes << condition(condition_id, button)
        nodes << reply(action_id, button)
        edges << { "from" => "entry_1", "to" => condition_id }
        edges << { "from" => condition_id, "to" => action_id }
      end

      { "schema_version" => 1, "nodes" => nodes, "edges" => edges, "viewport" => { "x" => 0, "y" => 0, "zoom" => 1 } }
    end

    private

    attr_reader :template

    def buttons
      Array(template.interactive_buttons).select { |button| button["actionable_reply"] }
    end

    def entry
      {
        "id" => "entry_1", "type" => "entry", "label" => "Quando o cliente clicar em um botão",
        "config" => { "trigger" => "whatsapp_flow_button", "entry_policy" => "future", "whatsapp_template_id" => template.id }
      }
    end

    def condition(id, button)
      {
        "id" => id, "type" => "response_condition", "label" => "Se botão: #{button['text']}",
        "config" => {
          "category" => "template_buttons", "field" => "interaction.button_payload", "operator" => "equals",
          "value" => button["key"].to_s, "button_key" => button["key"].to_s, "button_payload" => button["key"].to_s,
          "button_text" => button["text"].to_s, "match_strategy" => "button_payload_or_text"
        }
      }
    end

    def reply(id, button)
      {
        "id" => id, "type" => "action", "label" => "Responder: #{button['text']}",
        "config" => { "action_type" => "send_whatsapp", "message" => "Você escolheu “#{button['text']}”. Edite esta mensagem e continue a conversa por aqui." }
      }
    end
  end
end
