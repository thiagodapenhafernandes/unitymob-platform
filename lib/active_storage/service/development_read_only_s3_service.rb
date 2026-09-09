require "active_storage/service/digital_ocean_spaces_service"

module ActiveStorage
  # Imported blobs retain their original service name so reads keep working.
  # Development may detach them locally, but must never mutate their remote objects.
  class Service::DevelopmentReadOnlyS3Service < Service::DigitalOceanSpacesService
    def upload(*)
      raise IOError, "Armazenamento de origem somente para leitura em desenvolvimento"
    end

    def url_for_direct_upload(*)
      raise IOError, "Upload direto permitido apenas no armazenamento de desenvolvimento"
    end

    def compose(*)
      raise IOError, "Composição bloqueada no armazenamento de origem"
    end

    def delete(*)
      # Active Storage may remove the local reference; retain the shared object.
    end

    def delete_prefixed(*)
      # Includes derived variants belonging to the production database.
    end
  end
end
