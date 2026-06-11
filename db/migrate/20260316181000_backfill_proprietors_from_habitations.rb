class BackfillProprietorsFromHabitations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    say_with_time "Backfilling proprietors from habitations" do
      Habitation.reset_column_information
      Proprietor.reset_column_information

      Habitation.where(proprietor_id: nil).find_each do |habitation|
        name = habitation.proprietario.to_s.strip
        email = habitation.proprietario_email.to_s.strip
        mobile = habitation.proprietario_celular.to_s.strip
        vista_code = habitation.proprietario_codigo.to_s.strip
        next if name.blank? && email.blank? && mobile.blank? && vista_code.blank?

        proprietor = nil
        proprietor = Proprietor.find_by(vista_code: vista_code) if vista_code.present?
        proprietor ||= Proprietor.find_by(email: email) if email.present?
        proprietor ||= Proprietor.find_by(name: name) if name.present?
        proprietor ||= Proprietor.create!(name: (name.presence || "Proprietário sem nome"), role: :owner)

        updates = {}
        updates[:name] = name if name.present? && proprietor.name.blank?
        updates[:email] = email if email.present? && proprietor.email.blank?
        updates[:mobile_phone] = mobile if mobile.present? && proprietor.mobile_phone.blank?
        updates[:vista_code] = vista_code if vista_code.present? && proprietor.vista_code.blank?
        proprietor.update_columns(updates) if updates.any?

        habitation.update_columns(proprietor_id: proprietor.id)
      end
    end
  end

  def down
    # no-op
  end
end
