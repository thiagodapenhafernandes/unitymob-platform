module Meta
  class ConnectionCompletion
    class PermissionLoss < StandardError; end

    def self.call(integration:, identity:, preserve_permissions: false)
      previous_token = integration.access_token
      if preserve_permissions && integration.persisted? && integration.access_token.present?
        unless integration.facebook_user_id.to_s == identity.fetch('facebook_user_id').to_s
          raise PermissionLoss, 'Use a conexão legada para trocar a conta Facebook.'
        end
        current = Facebook::PermissionCheck.statuses(integration.access_token).select { |_, status| status == 'granted' }.keys
        unless current.present? && (current - identity.fetch('granted_permissions')).empty?
          raise PermissionLoss, 'O novo acesso não preserva as permissões atuais. Use a conexão legada.'
        end
      end
      token_info = Facebook::MetaService.exchange_access_token(identity.fetch('access_token'))
      new_token = token_info&.fetch('access_token', nil) || identity.fetch('access_token')
      preserve_asset_access!(previous_token, new_token, identity) if preserve_permissions && previous_token.present?
      integration.with_lock do
        if preserve_permissions && integration.access_token != previous_token
          raise PermissionLoss, 'A conexão foi alterada durante a autorização. Inicie novamente.'
        end
        integration.update!(access_token: new_token,
          facebook_user_id: identity.fetch('facebook_user_id'), name: identity['name'], email: identity['email'],
          token_expires_at: token_info&.fetch('expires_in', nil) ? Time.current + token_info['expires_in'].to_i.seconds : nil)
        job = MetaSyncJob.perform_later(integration.id)
        raise 'Meta synchronization unavailable' if job == false
      end
      integration
    end

    def self.preserve_asset_access!(previous_token, new_token, identity)
      previous, replacement = [previous_token, new_token].map { |token| Facebook::PermissionCheck.token_access(token) }
      valid = [previous, replacement].all? do |access|
        access.is_a?(Hash) && access['is_valid'] == true &&
          access['app_id'] == ENV['FACEBOOK_APP_ID'] && access['user_id'].to_s == identity['facebook_user_id'].to_s &&
          access['scopes'].is_a?(Array) && access['scopes'].any? && access['granular_scopes'].is_a?(Array)
      end
      raise PermissionLoss, 'Não foi possível conferir os ativos autorizados. Sua conexão atual foi preservada.' unless valid

      current_targets = previous['granular_scopes'].index_by { |scope| scope.fetch('scope') }
      new_targets = replacement['granular_scopes'].index_by { |scope| scope.fetch('scope') }
      preserved = (previous['scopes'] - replacement['scopes']).empty? && previous['scopes'].all? do |scope|
        old_ids = current_targets.dig(scope, 'target_ids')
        new_ids = new_targets.dig(scope, 'target_ids')
        old_ids.is_a?(Array) ? new_ids.is_a?(Array) && (old_ids - new_ids).empty? : new_ids.nil?
      end
      raise PermissionLoss, 'O novo acesso reduz os ativos autorizados. Use a conexão legada.' unless preserved
    end
    private_class_method :preserve_asset_access!
  end
end
