namespace :vista do
  desc "Diagnostica os anexos do Vista para os códigos informados (read-only)"
  task diagnose_documents: :environment do
    codes = ENV.fetch("CODES", "").split(",").map(&:strip).reject(&:blank?)
    if codes.empty?
      puts "Informe os códigos: CODES=8376[,8930] bundle exec rake vista:diagnose_documents"
      next
    end

    service = Vista::PropertyReconciliationService.new(codigos: codes, dry_run: true, download_files: false)

    codes.each do |codigo|
      puts "=" * 70
      begin
        result = service.document_diagnostics(codigo)
        puts "Imóvel #{codigo}: campo Anexo presente? #{result[:anexo_present]} | brutos: #{result[:raw_count]} | parseados: #{result[:parsed_count]}"

        puts "  -> Nenhum anexo retornado pela API para este imóvel." if result[:documents].empty?

        result[:documents].each do |doc|
          puts "  [#{doc[:index]}] destino=#{doc[:target]} importavel=#{doc[:importable]}"
          puts "      chaves: #{doc[:keys].join(', ')}"
          puts "      Descricao=#{doc[:descricao].inspect} Anexo=#{doc[:anexo].inspect} Arquivo=#{doc[:arquivo].inspect} URLlike=#{doc[:url_like].inspect}"
          puts "      source_url=#{doc[:source_url].inspect}"
          puts "      filename=#{doc[:filename].inspect}"
        end
      rescue StandardError => e
        puts "  ERRO ao consultar #{codigo}: #{e.class} - #{e.message}"
      end
    end

    puts "=" * 70
    puts "Diagnóstico concluído (nenhuma alteração gravada)."
  end
end
