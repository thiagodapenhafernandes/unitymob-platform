module Storage
  module Routing
    PROPERTY_PHOTO_ATTACHMENT = ["Habitation", "photos"].freeze
    PROPERTY_DOCUMENT_ATTACHMENTS = [
      ["Habitation", "fichas_cadastro"],
      ["Habitation", "autorizacoes_venda"]
    ].freeze

    module_function

    def service_name_for(record:, name:)
      setting = StorageIntegrationSetting.current
      key = [record.class.name, name.to_s]

      if key == PROPERTY_PHOTO_ATTACHMENT
        setting.photo_service_name
      elsif PROPERTY_DOCUMENT_ATTACHMENTS.include?(key)
        setting.document_service_name
      else
        setting.document_service_name
      end
    end

    def service_name_for_vista_asset(asset)
      setting = StorageIntegrationSetting.current
      asset.kind == "property_photo" ? setting.photo_service_name : setting.document_service_name
    end

    def public_property_photo_attachment?(attachment)
      Storage::PublicPropertyPhoto.public_attachment?(attachment)
    end
  end
end
