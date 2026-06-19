namespace :system_admin do
  desc "Concede acesso de Admin do Sistema: rake system_admin:grant[email@dominio.com]"
  task :grant, [:email] => :environment do |_t, args|
    user = AdminUser.find_by(email: args[:email])
    abort("Usuário não encontrado: #{args[:email]}") unless user
    user.update_column(:super_admin, true)
    puts "OK: #{user.email} agora é Admin do Sistema."
  end

  desc "Revoga acesso de Admin do Sistema: rake system_admin:revoke[email@dominio.com]"
  task :revoke, [:email] => :environment do |_t, args|
    user = AdminUser.find_by(email: args[:email])
    abort("Usuário não encontrado: #{args[:email]}") unless user
    user.update_column(:super_admin, false)
    puts "OK: #{user.email} não é mais Admin do Sistema."
  end

  desc "Lista os Admins do Sistema atuais"
  task list: :environment do
    admins = AdminUser.where(super_admin: true).order(:name)
    if admins.empty?
      puts "Nenhum Admin do Sistema cadastrado."
    else
      admins.each { |u| puts "- #{u.name} <#{u.email}>" }
    end
  end
end
