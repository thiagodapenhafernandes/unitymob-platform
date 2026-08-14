# Criar primeiro usuário admin
default_admin_email = ENV.fetch('SEED_ADMIN_EMAIL', 'admin@example.com')
default_admin_password = ENV.fetch('SEED_ADMIN_PASSWORD', 'change-me-123456')

AdminUser.find_or_create_by!(email: default_admin_email) do |admin|
  admin.name = 'Administrador'
  admin.password = default_admin_password
  admin.password_confirmation = default_admin_password
  admin.role = :admin
end

puts "✅ Admin user criado: #{default_admin_email}"
