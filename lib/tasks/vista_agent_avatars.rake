namespace :vista_agents do
  desc "Baixa fotos dos corretores do Vista e anexa em AdminUser.avatar"
  task download_avatars: :environment do
    result = Vista::AgentAvatarDownloadService.new(
      dry_run: ENV.fetch("DRY_RUN", "false")
    ).call

    puts "Vista agent avatars download"
    puts "  Ambiente: #{Rails.env}"
    puts "  ActiveStorage service: #{ActiveStorage::Blob.service.name}"
    puts "  Lidos: #{result.scanned}"
    puts "  Baixados/anexados: #{result.downloaded}"
    puts "  Ignorados: #{result.skipped}"
    puts "  Falhas: #{result.failed}"

    if result.errors.any?
      puts "  Erros:"
      result.errors.first(20).each do |error|
        puts "    ##{error[:admin_user_id]} #{error[:email]} #{error[:source_photo_path]}: #{error[:error]}"
      end
      omitted = result.errors.size - 20
      puts "    ... #{omitted} erro(s) omitido(s)" if omitted.positive?
    end
  end
end
