# Criar primeiro usuário admin
AdminUser.find_or_create_by!(email: 'admin@saluteimoveis.com.br') do |admin|
  admin.name = 'Administrador'
  admin.password = 'salute2024'
  admin.password_confirmation = 'salute2024'
  admin.role = :admin
end

puts "✅ Admin user criado: admin@saluteimoveis.com.br / salute2024"
