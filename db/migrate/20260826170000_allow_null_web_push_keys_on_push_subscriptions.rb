# frozen_string_literal: true

# Push nativo (iOS/Android via Capacitor) não usa as chaves criptográficas do
# Web Push (VAPID) — só um device token. platform já previa "ios"/"android"
# desde a criação da tabela (comentário original), então isso só relaxa a
# obrigatoriedade das colunas específicas de Web Push.
class AllowNullWebPushKeysOnPushSubscriptions < ActiveRecord::Migration[7.1]
  def change
    change_column_null :push_subscriptions, :p256dh, true
    change_column_null :push_subscriptions, :auth, true
  end
end
