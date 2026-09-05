Rails.application.config.to_prepare do
  ActionController::Base.include Support::AssistedGuard unless ActionController::Base < Support::AssistedGuard
end
Rails.application.config.filter_parameters += [:support_access_id, :token]
