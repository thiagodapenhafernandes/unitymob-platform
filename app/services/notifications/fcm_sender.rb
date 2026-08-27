# frozen_string_literal: true

require "faraday"
require "googleauth"
require "stringio"

module Notifications
  # Envia push nativo (iOS/Android) via Firebase Cloud Messaging (API HTTP v1).
  # Credenciais pendentes de configuração — ver README de mobile/ para o passo
  # a passo de criar o projeto Firebase e obter a service account key.
  #
  # ENV esperadas:
  #   FCM_PROJECT_ID           — id do projeto Firebase
  #   FCM_SERVICE_ACCOUNT_JSON — conteúdo JSON da service account (não o path)
  class FcmSender
    FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

    Result = Struct.new(:success?, :status, :body, keyword_init: true)

    def self.configured?
      new.configured?
    end

    def self.deliver(token:, title:, body:, data: {})
      new.deliver(token: token, title: title, body: body, data: data)
    end

    def configured?
      project_id.present? && service_account_json.present?
    end

    def deliver(token:, title:, body:, data: {})
      unless configured?
        return Result.new(success?: false, status: nil, body: "FCM não configurado (defina FCM_PROJECT_ID e FCM_SERVICE_ACCOUNT_JSON)")
      end

      response = connection.post("/v1/projects/#{project_id}/messages:send") do |req|
        req.headers["Authorization"] = "Bearer #{access_token}"
        req.headers["Content-Type"] = "application/json"
        req.body = {
          message: {
            token: token,
            notification: { title: title, body: body }.compact,
            data: data.transform_values(&:to_s)
          }.compact
        }.to_json
      end

      Result.new(success?: response.success?, status: response.status, body: response.body)
    rescue Faraday::Error => e
      Result.new(success?: false, status: nil, body: e.message)
    end

    private

    def project_id
      ENV["FCM_PROJECT_ID"]
    end

    def service_account_json
      ENV["FCM_SERVICE_ACCOUNT_JSON"]
    end

    def access_token
      credentials.fetch_access_token!["access_token"]
    end

    def credentials
      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(service_account_json),
        scope: FCM_SCOPE
      )
    end

    def connection
      @connection ||= Faraday.new(url: "https://fcm.googleapis.com")
    end
  end
end
