# Active Record Encryption configurado por ENV (não usamos credentials/master.key
# neste ambiente). Gere as três chaves uma vez com:
#
#   bin/rails db:encryption:init
#
# e exporte como variáveis de ambiente no deploy (e em .env.development localmente):
#
#   AR_ENCRYPTION_PRIMARY_KEY
#   AR_ENCRYPTION_DETERMINISTIC_KEY
#   AR_ENCRYPTION_KEY_DERIVATION_SALT
#
# Sem essas chaves, atributos declarados com `encrypts` (senha SMTP, chave privada
# VAPID etc.) não conseguem ser lidos/gravados — as telas de configuração avisam
# quando a criptografia não está disponível (EmailSetting/PushSetting#encryption_ready?).
primary_key      = ENV["AR_ENCRYPTION_PRIMARY_KEY"]
deterministic_key = ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"]
key_derivation_salt = ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"]

if primary_key.present? && deterministic_key.present? && key_derivation_salt.present?
  Rails.application.config.active_record.encryption.primary_key = primary_key
  Rails.application.config.active_record.encryption.deterministic_key = deterministic_key
  Rails.application.config.active_record.encryption.key_derivation_salt = key_derivation_salt
  # Suporta ler dados ainda não criptografados (migração suave de colunas existentes).
  Rails.application.config.active_record.encryption.support_unencrypted_data = true
elsif !Rails.env.test?
  Rails.logger.warn(
    "[ActiveRecordEncryption] chaves ausentes — defina AR_ENCRYPTION_PRIMARY_KEY, " \
    "AR_ENCRYPTION_DETERMINISTIC_KEY e AR_ENCRYPTION_KEY_DERIVATION_SALT. " \
    "Configurações com credenciais criptografadas (SMTP/VAPID) ficarão indisponíveis."
  )
end
