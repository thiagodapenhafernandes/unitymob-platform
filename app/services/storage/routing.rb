module Storage
  module Routing
    PROPERTY_PHOTO_ATTACHMENT = ["Habitation", "photos"].freeze
    PROPERTY_DOCUMENT_ATTACHMENTS = [
      ["Habitation", "fichas_cadastro"],
      ["Habitation", "autorizacoes_venda"]
    ].freeze

    module_function

    def service_name_for(record:, name:)
      setting = StorageIntegrationSetting.current(tenant: record_tenant(record))
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
      setting = StorageIntegrationSetting.current(tenant: asset_tenant(asset))
      asset.kind == "property_photo" ? setting.photo_service_name : setting.document_service_name
    end

    def public_property_photo_attachment?(attachment)
      Storage::PublicPropertyPhoto.public_attachment?(attachment)
    end

    def record_tenant(record)
      record.respond_to?(:tenant) ? record.tenant : Current.tenant
    end

    def asset_tenant(asset)
      if asset.respond_to?(:habitation) && asset.habitation.respond_to?(:tenant)
        asset.habitation.tenant
      elsif asset.respond_to?(:tenant)
        asset.tenant
      else
        Current.tenant
      end
    end
  end
end
