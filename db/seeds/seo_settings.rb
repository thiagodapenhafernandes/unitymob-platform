# Popular SEO Settings para páginas principais
puts "Creating SEO settings for main pages..."

# Home
SeoSetting.find_or_create_by!(page_name: 'home') do |seo|
  seo.meta_title = 'Sua Imobiliária | Encontre seu Imóvel Ideal'
  seo.meta_description = 'Encontre imóveis para venda e locação. Apartamentos, casas, coberturas e muito mais com atendimento especializado.'
  seo.meta_keywords = 'imóveis, apartamentos venda, casas aluguel, imobiliária'
  puts "  ✓ Home"
end

# Sobre
SeoSetting.find_or_create_by!(page_name: 'sobre') do |seo|
  seo.meta_title = 'Sobre Nós | Sua Imobiliária'
  seo.meta_description = 'Conheça nossa imobiliária, equipe e forma de atendimento no mercado imobiliário.'
  seo.meta_keywords = 'sobre imobiliária, empresa imóveis, atendimento imobiliário'
  puts "  ✓ Sobre"
end

# Contato
SeoSetting.find_or_create_by!(page_name: 'contato') do |seo|
  seo.meta_title = 'Contato | Sua Imobiliária'
  seo.meta_description = 'Entre em contato com nossa equipe. Estamos prontos para ajudar você a encontrar o imóvel ideal.'
  seo.meta_keywords = 'contato imobiliária, falar com corretor, atendimento imobiliária'
  puts "  ✓ Contato"
end

# Corretores
SeoSetting.find_or_create_by!(page_name: 'corretores') do |seo|
  seo.meta_title = 'Nossos Corretores | Sua Imobiliária'
  seo.meta_description = 'Conheça nossa equipe de corretores especializados. Profissionais qualificados para ajudar você a encontrar o imóvel ideal.'
  seo.meta_keywords = 'corretores, equipe imobiliária, corretor imóveis'
  puts "  ✓ Corretores"
end

# Trabalhe Conosco
SeoSetting.find_or_create_by!(page_name: 'trabalhe_conosco') do |seo|
  seo.meta_title = 'Trabalhe Conosco | Sua Imobiliária'
  seo.meta_description = 'Faça parte da nossa equipe. Oportunidades para corretores e profissionais do mercado imobiliário.'
  seo.meta_keywords = 'trabalhar em imobiliária, vaga corretor, carreira imobiliária'
  puts "  ✓ Trabalhe Conosco"
end

# Corporativos
SeoSetting.find_or_create_by!(page_name: 'corporativos') do |seo|
  seo.meta_title = 'Imóveis Corporativos | Sua Imobiliária'
  seo.meta_description = 'Galpões, salas comerciais, terrenos e imóveis corporativos. Soluções para sua empresa.'
  seo.meta_keywords = 'galpões, sala comercial, imóvel comercial, terreno loteamento'
  puts "  ✓ Corporativos"
end

# Busca de Imóveis
SeoSetting.find_or_create_by!(page_name: 'imoveis') do |seo|
  seo.meta_title = 'Buscar Imóveis | Sua Imobiliária'
  seo.meta_description = 'Busque imóveis para venda e locação. Filtros avançados para encontrar o imóvel ideal.'
  seo.meta_keywords = 'buscar imóveis, venda aluguel, apartamentos casas'
  puts "  ✓ Imóveis"
end

puts "\n✅ SEO Settings created successfully!"
