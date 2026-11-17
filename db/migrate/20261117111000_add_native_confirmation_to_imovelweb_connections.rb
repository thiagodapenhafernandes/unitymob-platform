class AddNativeConfirmationToImovelwebConnections < ActiveRecord::Migration[7.1]
  def change
    add_column :imovelweb_connections, :consent_confirmed_at, :datetime
    add_column :imovelweb_connections, :binding_email_hint, :string
    add_column :imovelweb_connections, :binding_challenge_token, :text
    add_column :imovelweb_connections, :binding_proof, :text
  end
end
