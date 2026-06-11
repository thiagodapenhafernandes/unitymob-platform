# frozen_string_literal: true

# Tasks para gerenciar a base GeoLite2-City da MaxMind.
# Requer uma conta gratuita em https://www.maxmind.com/en/geolite2/signup
# e a chave de licença em ENV["MAXMIND_LICENSE_KEY"].
namespace :geoip do
  desc "Baixa GeoLite2-City.mmdb para db/geoip/"
  task :download do
    key = ENV["MAXMIND_LICENSE_KEY"]
    if key.to_s.strip.empty?
      abort "Defina MAXMIND_LICENSE_KEY no ambiente. Crie conta grátis em maxmind.com/en/geolite2/signup."
    end

    require "net/http"
    require "fileutils"
    require "tmpdir"

    target_dir = Rails.root.join("db", "geoip")
    FileUtils.mkdir_p(target_dir)
    target = target_dir.join("GeoLite2-City.mmdb")

    url = URI("https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=#{key}&suffix=tar.gz")
    puts "Baixando GeoLite2-City..."

    Dir.mktmpdir do |tmp|
      tarball = File.join(tmp, "geolite.tar.gz")
      Net::HTTP.start(url.host, url.port, use_ssl: true) do |http|
        resp = http.get(url.request_uri)
        raise "HTTP #{resp.code}: #{resp.body[0..200]}" unless resp.code == "200"
        File.binwrite(tarball, resp.body)
      end

      system("tar -xzf #{tarball} -C #{tmp}") or abort "Falha ao extrair tarball."

      extracted = Dir[File.join(tmp, "GeoLite2-City_*", "GeoLite2-City.mmdb")].first
      abort "Arquivo .mmdb não encontrado no tarball." if extracted.nil?

      FileUtils.cp(extracted, target)
    end

    puts "OK — base salva em #{target}"
  end

  desc "Teste: resolve um IP contra a base baixada"
  task test: :environment do
    require "maxmind/db"
    path = Rails.root.join("db", "geoip", "GeoLite2-City.mmdb")
    abort "Base não encontrada em #{path}. Rode rake geoip:download primeiro." unless File.exist?(path)

    reader = MaxMind::DB.new(path.to_s, mode: MaxMind::DB::MODE_MEMORY)
    sample_ip = ENV["IP"] || "8.8.8.8"
    result = reader.get(sample_ip)
    puts JSON.pretty_generate(result || { error: "IP não encontrado" })
  end
end
