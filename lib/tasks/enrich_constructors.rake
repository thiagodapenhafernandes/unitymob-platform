require 'open-uri'

namespace :enrich do
  desc "Fetch and attach logos for constructors using domains"
  task logos: :environment do
    puts "--- Iniciando enriquecimento de logos ---"
    
    Constructor.where.not(website_url: nil).each do |con|
      next if con.logo.attached?
      
      domain = con.website_url.gsub(/^https?:\/\//, '').gsub(/\/$/, '')
      logo_url = "https://logo.clearbit.com/#{domain}?size=256"
      
      begin
        puts "Processando #{con.name} (#{domain})..."
        file = URI.open(logo_url)
        con.logo.attach(io: file, filename: "logo_#{con.id}.png", content_type: 'image/png')
        puts "  [OK] Logo capturado e anexado!"
      rescue OpenURI::HTTPError => e
        puts "  [Erro] Logo não encontrado via Clearbit para #{domain}"
      rescue => e
        puts "  [Erro] Falha ao processar #{con.name}: #{e.message}"
      end
    end
    
    puts "--- Enriquecimento concluído! ---"
  end
end
