namespace :seo do
  desc "Backfill public SEO settings for property detail pages"
  task backfill_property_settings: :environment do
    result = Seo::PropertySettingsBackfill.new.call

    puts "SEO property settings backfill"
    puts "Evaluated: #{result.evaluated}"
    puts "Created: #{result.created}"
    puts "Updated: #{result.updated}"
    puts "Skipped manual: #{result.skipped}"
    puts "Errors: #{result.errors}"
  end
end
