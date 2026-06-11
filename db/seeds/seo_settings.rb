# Popular SEO Settings para páginas principais
puts "Creating SEO settings for main pages..."

# Home
SeoSetting.find_or_create_by!(page_name: 'home') do |seo|
  seo.meta_title = 'Salute Imóveis | Imóveis em Balneário Camboriú'
  seo.meta_description = 'Encontre os melhores imóveis para venda e locação em Balneário Camboriú. Apartamentos, casas, coberturas e muito mais na Salute Imóveis.'
  seo.meta_keywords = 'imóveis balneário camboriú, apartamentos venda, casas aluguel, imobiliária bc'
  puts "  ✓ Home"
end

# Sobre
SeoSetting.find_or_create_by!(page_name: 'sobre') do |seo|
  seo.meta_title = 'Sobre Nós | Salute Imóveis'
  seo.meta_description = 'Conheça a Salute Imóveis, sua imobiliária de confiança em Balneário Camboriú. Tradição e excelência no mercado imobiliário.'
  seo.meta_keywords = 'sobre salute, imobiliária balneário camboriú, empresa imóveis'
  puts "  ✓ Sobre"
end

# Contato
SeoSetting.find_or_create_by!(page_name: 'contato') do |seo|
  seo.meta_title = 'Contato | Salute Imóveis'
  seo.meta_description = 'Entre em contato com a Salute Imóveis. Estamos prontos para ajudar você a encontrar o imóvel perfeito em Balneário Camboriú.'
  seo.meta_keywords = 'contato salute, falar com corretor, atendimento imobiliária'
  puts "  ✓ Contato"
end

# Corretores
SeoSetting.find_or_create_by!(page_name: 'corretores') do |seo|
  seo.meta_title = 'Nossos Corretores | Salute Imóveis'
  seo.meta_description = 'Conheça nossa equipe de corretores especializados. Profissionais qualificados para ajudar você a encontrar o imóvel ideal.'
  seo.meta_keywords = 'corretores balneário camboriú, equipe salute, corretor imóveis'
  puts "  ✓ Corretores"
end

# Trabalhe Conosco
SeoSetting.find_or_create_by!(page_name: 'trabalhe_conosco') do |seo|
  seo.meta_title = 'Trabalhe Conosco | Salute Imóveis'
  seo.meta_description = 'Faça parte da equipe Salute Imóveis. Oportunidades para corretores e profissionais do mercado imobiliário.'
  seo.meta_keywords = 'trabalhar salute, vaga corretor, carreira imobiliária'
  puts "  ✓ Trabalhe Conosco"
end

# Corporativos
SeoSetting.find_or_create_by!(page_name: 'corporativos') do |seo|
  seo.meta_title = 'Imóveis Corporativos | Salute Imóveis'
  seo.meta_description = 'Galpões, salas comerciais, terrenos e imóveis corporativos em Balneário Camboriú e região. Soluções para sua empresa.'
  seo.meta_keywords = 'galpões bc, sala comercial, imóvel comercial, terreno loteamento'
  puts "  ✓ Corporativos"
end

# Busca de Imóveis
SeoSetting.find_or_create_by!(page_name: 'imoveis') do |seo|
  seo.meta_title = 'Buscar Imóveis | Salute Imóveis'
  seo.meta_description = 'Busque imóveis para venda e locação em Balneário Camboriú. Filtros avançados para encontrar o imóvel perfeito.'
  seo.meta_keywords = 'buscar imóveis, venda aluguel bc, apartamentos casas'
  puts "  ✓ Imóveis"
end

puts "\n✅ SEO Settings created successfully!"
