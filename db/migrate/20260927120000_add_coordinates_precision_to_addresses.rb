# Marca coordenadas que não vieram do endereço exato. "neighborhood" = centro
# do bairro (fallback quando o mapa não conhece a rua); o mapa público mostra
# esses casos só como região aproximada. Nulo = coordenada do endereço (import,
# pino manual ou geocodificação da rua), comportamento de antes.
class AddCoordinatesPrecisionToAddresses < ActiveRecord::Migration[7.1]
  def change
    add_column :addresses, :coordinates_precision, :string
  end
end
