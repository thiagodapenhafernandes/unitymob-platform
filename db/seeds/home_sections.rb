# namespace :home_sections do
#   desc "Create default home sections"
#   task seed: :environment do
#     puts "Creating default home sections..."

HomeSection.find_or_create_by!(section_type: 'featured_properties') do |section|
  section.title = 'Imóveis em Destaque'
  section.subtitle = 'Confira nossa seleção exclusiva de imóveis'
  section.active = true
  section.order_position = 1
  puts "  ✓ Created: Featured Properties"
end

HomeSection.find_or_create_by!(section_type: 'opportunities') do |section|
  section.title = 'Oportunidades'
  section.subtitle = 'Imóveis com preços especiais - não perca!'
  section.active = true
  section.order_position = 2
  puts "  ✓ Created: Opportunities"
end

HomeSection.find_or_create_by!(section_type: 'developments') do |section|
  section.title = 'Empreendimentos'
  section.subtitle = 'Conheça nossos melhores projetos imobiliários'
  section.active = true
  section.order_position = 3
  puts "  ✓ Created: Developments"
end

HomeSection.find_or_create_by!(section_type: 'rentals') do |section|
  section.title = 'Imóveis para Locação'
  section.subtitle = 'Encontre o imóvel perfeito para alugar'
  section.active = true
  section.order_position = 4
  puts "  ✓ Created: Rentals"
end

puts "\n✅ Default home sections created successfully!"

#   end
# end
