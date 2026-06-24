module Storage
  class PublicImageResolver
    def self.resolve(source, **options)
      Storage::PublicCdnImageUrl.resolve(source, **options)
    end
  end
end
