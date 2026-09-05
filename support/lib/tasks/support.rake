namespace :support do
  desc 'Reconcilia automaticamente as contas deste servidor com a central'
  task connect: :environment do
    abort 'Execute no CRM com a infraestrutura de suporte configurada' unless Support::Registration.enabled?
    Support::RegisterAccountsJob.perform_now
    puts 'Contas reconciliadas; indisponibilidades serão recuperadas pela recorrência.'
  end

  desc 'Cria o primeiro administrador da central (não altera usuários existentes)'
  task bootstrap: :environment do
    abort 'Execute na aplicação central/' unless SupportDesk.central?
    abort 'Já existe administrador; utilize a interface de equipe' if Staff.where(role: 'admin').exists?
    staff = Staff.create!(name: ENV.fetch('SUPPORT_ADMIN_NAME'), email: ENV.fetch('SUPPORT_ADMIN_EMAIL'), role: 'admin')
    puts "Ativação válida por 1 hora: https://admin.unitymob.com.br/activate?token=#{staff.activation_token!}"
  end

  desc 'Entrega eventos pendentes com o mesmo mecanismo da recorrência'
  task dispatch: :environment do
    Support::DispatchJob.perform_now
  end
end
