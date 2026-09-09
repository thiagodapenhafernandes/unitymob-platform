require "digest"
require "json"

module Blog
  class WordpressImporter
    def initialize(tenant:, path:)
      @tenant = tenant
      @path = Pathname.new(path).realpath
      @directory = @path.dirname
      @data = JSON.parse(@path.read)
      @image_files = @data.fetch("images").to_h { |image| [image.fetch("source_url"), image.fetch("local_file")] }
      @blobs = {}
    end

    def call(execute: false)
      validate_backup!
      report = { tenant_id: @tenant.id, articles: @data.fetch("articles").size, imported: 0, skipped: 0, execute: execute }
      return report unless execute

      @data.fetch("articles").each do |source|
        if @tenant.blog_articles.exists?(wordpress_id: source.fetch("id"))
          report[:skipped] += 1
          next
        end
        import_article!(source)
        report[:imported] += 1
      end
      report
    end

    private

    def validate_backup!
      @data.fetch("articles").each do |source|
        next if @tenant.blog_articles.exists?(wordpress_id: source.fetch("id"))

        article = @tenant.blog_articles.new(title: source.fetch("title"), slug: source.fetch("slug"))
        article.valid?
        raise ArgumentError, "Endereço #{source['slug']}: #{article.errors[:slug].join(', ')}" if article.errors[:slug].any?
        image_urls(source).each { |url| local_file!(url) }
      end
    end

    def import_article!(source)
      # Uploads are reusable on retry; DB writes for each article commit together.
      html = Nokogiri::HTML.fragment(source.fetch("content"))
      html.css("script,style,iframe,form,input,button,video,audio").remove
      html.css("img").each do |image|
        blob = image_blob!(image["src"])
        replacement = ActionText::Attachment.from_attachable(blob, caption: image["alt"].presence).to_html
        image.replace(Nokogiri::HTML.fragment(replacement))
      end
      html.css("a[href]").each do |link|
        matching = @data.fetch("articles").find { |item| item["link"] == link["href"] }
        link["href"] = "/#{matching['slug']}" if matching
      end
      html.traverse do |node|
        next unless node.element?
        node.attribute_nodes.each { |attribute| node.remove_attribute(attribute.name) if attribute.name.start_with?("on", "data-") || %w[style class srcset sizes contenteditable].include?(attribute.name) }
      end
      cover = image_urls(source).first
      cover_blob = image_blob!(cover) if cover
      BlogArticle.transaction do
        categories = source.fetch("categories").map do |category|
          name = category.fetch("name") == "Uncategorized" ? "Geral" : category.fetch("name")
          slug = name == "Geral" ? "geral" : category.fetch("slug")
          @tenant.blog_categories.find_or_create_by!(slug: slug) { |record| record.name = name }
        end
        categories = [@tenant.blog_categories.find_or_create_by!(slug: "geral") { |record| record.name = "Geral" }] if categories.empty?
        article = @tenant.blog_articles.new(
          wordpress_id: source.fetch("id"), source_url: source.fetch("link"), title: source.fetch("title"), slug: source.fetch("slug"),
          excerpt: Nokogiri::HTML.fragment(source.fetch("excerpt")).text.squish.truncate(1000),
          status: source["status"] == "publish" ? "published" : "draft",
          published_at: Time.iso8601(source.fetch("date_gmt") + "Z"), content: html.to_html,
          blog_categories: categories, cover_alt: source.fetch("title"),
          meta_title: source.dig("seo", "title").to_s.truncate(250),
          meta_description: source.dig("seo", "og_description").to_s.truncate(500)
        )
        article.cover = cover_blob if cover_blob
        article.save!
      end
    end

    def image_urls(source)
      featured = source.fetch("images").find { |image| image["kind"] == "featured" }
      urls = Nokogiri::HTML.fragment(source.fetch("content")).css("img[src]").map { |image| image["src"] }
      [featured&.fetch("source_url", nil), *urls].compact.uniq
    end

    def local_file!(url)
      name = @image_files.fetch(url) { raise ArgumentError, "Imagem ausente no backup: #{url}" }
      file = @directory.join(name).realpath
      raise ArgumentError, "Arquivo fora do backup" unless file.to_s.start_with?(@directory.to_s + File::SEPARATOR)
      raise ArgumentError, "Imagem não encontrada: #{name}" unless file.file?
      file
    end

    def image_blob!(url)
      @blobs[url] ||= begin
        file = local_file!(url)
        digest = Digest::SHA256.file(file).hexdigest
        existing = ActiveStorage::Blob.where(service_name: Blog::Storage.service_name(@tenant)).where("metadata::jsonb @> ?::jsonb", { tenant_id: @tenant.id, purpose: "blog", wordpress_sha256: digest }.to_json).first
        if existing
          existing
        else
          type = Marcel::MimeType.for(file)
          raise ArgumentError, "Formato de imagem inválido: #{file.basename}" unless Blog::Storage::IMAGE_TYPES.include?(type)
          File.open(file, "rb") do |io|
            raise ArgumentError, "Imagem maior que 20 MB: #{file.basename}" if io.size > Blog::Storage::MAX_BYTES
            ActiveStorage::Blob.create_and_upload!(io: io, filename: file.basename.to_s, content_type: type, service_name: Blog::Storage.service_name(@tenant), metadata: { tenant_id: @tenant.id, purpose: "blog", wordpress_sha256: digest }.merge(Blog::Storage.image_metadata(file, type)))
          end
        end
      end
    end
  end
end
