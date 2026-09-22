class AddReceptiveResponseFlowToWhatsappSenderNumbers < ActiveRecord::Migration[7.1]
  def change
    add_reference :whatsapp_sender_numbers,
                  :receptive_response_flow,
                  null: true,
                  foreign_key: { to_table: :whatsapp_response_flows },
                  index: true
  end
end
