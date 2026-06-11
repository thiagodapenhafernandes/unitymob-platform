class HabitationBrokerAssignment < ApplicationRecord
  belongs_to :habitation
  belongs_to :admin_user

  enum role: { captador: 'Captador', promotor: 'Promotor', placa: 'Placa' }
  enum commission_type: { fixed: 'Preço', percentage: 'Porcentagem' }

  validates :role, presence: true
  validates :admin_user_id, presence: true
end
