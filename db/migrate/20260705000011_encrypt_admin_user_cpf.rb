class EncryptAdminUserCpf < ActiveRecord::Migration[7.1]
  # LGPD: CPF/RG dos corretores em texto puro. Não há busca SQL por essas
  # colunas — cifra direta at-rest, sem coluna determinística.
  def up
    AdminUser.reset_column_information
    say_with_time "cifrando CPF/RG de #{AdminUser.unscoped.count} usuários" do
      AdminUser.unscoped.find_each(batch_size: 500) do |user|
        user.encrypt
      rescue => e
        say "admin_user #{user.id}: #{e.message}", true
      end
    end
  end

  def down
    # Leitura convive com os dois formatos (support_unencrypted_data);
    # voltar a texto puro exigiria decrypt manual.
  end
end
