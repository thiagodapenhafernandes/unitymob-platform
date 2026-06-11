seed_files = %w[
  admin_users
  seo_settings
  home_sections
  field_checkin_settings
]

seed_files.each do |name|
  path = Rails.root.join("db/seeds/#{name}.rb")
  puts "\n▶ Rodando seed: #{name}"
  load path
end

puts "\n🎉 Seeds concluídos."
