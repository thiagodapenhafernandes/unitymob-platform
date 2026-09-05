unless Rails.env.test?
  Rails.application.config.action_mailer.delivery_method = :smtp
  Rails.application.config.action_mailer.raise_delivery_errors = true
  Rails.application.config.action_mailer.smtp_settings = {
    address: ENV.fetch('SMTP_ADDRESS', 'smtp.umbler.com'),
    port: ENV.fetch('SMTP_PORT', 587).to_i,
    domain: 'unitymob.com.br',
    user_name: ENV['SMTP_USERNAME'],
    password: ENV['SMTP_PASSWORD'],
    authentication: :plain,
    enable_starttls: true,
    enable_starttls_auto: false,
    open_timeout: 5,
    read_timeout: 10
  }
end
