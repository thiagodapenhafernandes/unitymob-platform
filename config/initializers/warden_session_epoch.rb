# frozen_string_literal: true

# "Encerrar todas as sessões" por conta (tela Segurança de Acesso):
# toda sessão de admin recebe um carimbo (signed_in_at) quando o warden seta o
# usuário fora do :fetch — login normal, sign_in pós-2FA e helpers de teste.
# O bypass_sign_in (troca de conta/impersonação) não roda callbacks, mas
# preserva o hash de sessão do warden, então o carimbo do login original
# permanece válido. Se o dono marcar tenants.session_epoch_at, sessões
# carimbadas antes do epoch (ou sem carimbo) caem no próximo request.
module AdminSessionEpoch
  SESSION_KEY = "signed_in_at"

  module_function

  def stamp!(session_data)
    session_data[SESSION_KEY] = Time.current.to_i
  end

  def exempt_cache_key(tenant_id)
    "session_epoch_exempt:#{tenant_id}"
  end

  # O autor do "Encerrar todas as sessões" ganha isenção de 2 minutos: uma
  # request em voo de outra aba dele (cookie com carimbo antigo) re-carimba
  # em vez de derrubá-lo — sem isso, o Set-Cookie do sign_out dessa request
  # sobrescreveria o cookie re-carimbado e o dono cairia junto.
  def exempt?(record)
    tenant_id = record.respond_to?(:tenant_id) ? record.tenant_id : nil
    return false if tenant_id.blank?

    Rails.cache.read(exempt_cache_key(tenant_id)) == record.id
  rescue StandardError
    false
  end

  # Sessão anterior ao epoch da conta deve ser encerrada. Tolerante
  # pré-migration 20260707000002 (has_attribute?).
  def expired?(record, session_data)
    tenant = record.respond_to?(:tenant) ? record.tenant : nil
    return false unless tenant&.has_attribute?(:session_epoch_at)

    epoch = tenant.session_epoch_at
    return false if epoch.blank?

    stamp = session_data[SESSION_KEY]
    stamp.nil? || stamp.to_i < epoch.to_i
  end
end

Warden::Manager.after_set_user do |record, warden, options|
  scope = options[:scope]

  if record.is_a?(AdminUser) && options[:store] != false && warden.authenticated?(scope)
    if options[:event] != :fetch
      AdminSessionEpoch.stamp!(warden.session(scope))
    elsif AdminSessionEpoch.expired?(record, warden.session(scope))
      if AdminSessionEpoch.exempt?(record)
        AdminSessionEpoch.stamp!(warden.session(scope))
      else
        # Mesmo padrão do hook de timeoutable do Devise: derruba e sinaliza o
        # failure app com a mensagem própria (devise.failure.session_expired).
        proxy = Devise::Hooks::Proxy.new(warden)
        Devise.sign_out_all_scopes ? proxy.sign_out : proxy.sign_out(scope)
        throw :warden, scope: scope, message: :session_expired
      end
    end
  end
end
