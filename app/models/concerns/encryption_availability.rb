# Disponibilidade do Active Record Encryption (chaves via ENV neste projeto).
# Settings com credenciais criptografadas usam isto para degradar com elegância
# quando as chaves não estão configuradas, em vez de estourar exceção.
module EncryptionAvailability
  extend ActiveSupport::Concern

  class_methods do
    def encryption_ready?
      ENV["AR_ENCRYPTION_PRIMARY_KEY"].present? &&
        ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"].present? &&
        ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"].present?
    end
  end

  def encryption_ready?
    self.class.encryption_ready?
  end
end
