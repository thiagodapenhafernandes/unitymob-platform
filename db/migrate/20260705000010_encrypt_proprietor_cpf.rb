class EncryptProprietorCpf < ActiveRecord::Migration[7.1]
  # LGPD: CPF/CNPJ do proprietário (e do cônjuge) ficava em texto puro e era
  # consultado via regexp/ILIKE no SQL. Passa a:
  # - cpf_cnpj / spouse_cpf_cnpj cifrados at-rest (AR Encryption, no lugar);
  # - colunas *_digits (só números) com cifra DETERMINÍSTICA para busca por
  #   igualdade (find_by, unicidade e filtros das telas).
  # Busca parcial por pedaço do CPF deixa de existir por design (cifra).
  def up
    add_column :proprietors, :cpf_cnpj_digits, :string unless column_exists?(:proprietors, :cpf_cnpj_digits)
    add_column :proprietors, :spouse_cpf_cnpj_digits, :string unless column_exists?(:proprietors, :spouse_cpf_cnpj_digits)

    unless index_exists?(:proprietors, [:tenant_id, :cpf_cnpj_digits], name: :idx_proprietors_on_tenant_cpf_digits)
      add_index :proprietors, [:tenant_id, :cpf_cnpj_digits], name: :idx_proprietors_on_tenant_cpf_digits
    end

    # Backfill via model: escreve os digits cifrados e re-salva o cpf_cnpj
    # (que passa a ser gravado cifrado). support_unencrypted_data mantém a
    # leitura dos registros ainda não convertidos.
    Proprietor.reset_column_information
    say_with_time "cifrando CPFs de #{Proprietor.unscoped.count} proprietários" do
      Proprietor.unscoped.find_each(batch_size: 500) do |proprietor|
        proprietor.cpf_cnpj_digits = Proprietor.normalized_cpf_cnpj(proprietor.cpf_cnpj).presence
        proprietor.spouse_cpf_cnpj_digits = Proprietor.normalized_cpf_cnpj(proprietor.spouse_cpf_cnpj).presence
        proprietor.save!(validate: false, touch: false)
        # re-grava TODOS os atributos cifráveis (atribuir o mesmo valor não
        # marca dirty — encrypt força a cifra in-place do texto puro legado)
        proprietor.encrypt
      rescue => e
        say "proprietor #{proprietor.id}: #{e.message}", true
      end
    end
  end

  def down
    remove_index :proprietors, name: :idx_proprietors_on_tenant_cpf_digits if index_exists?(:proprietors, [:tenant_id, :cpf_cnpj_digits], name: :idx_proprietors_on_tenant_cpf_digits)
    remove_column :proprietors, :spouse_cpf_cnpj_digits if column_exists?(:proprietors, :spouse_cpf_cnpj_digits)
    remove_column :proprietors, :cpf_cnpj_digits if column_exists?(:proprietors, :cpf_cnpj_digits)
    # cpf_cnpj cifrado continua legível pelo app (support_unencrypted_data
    # convive com os dois formatos); voltar a texto puro exigiria decrypt manual.
  end
end
