module Vista
  class ImportAgentsService
    require 'open-uri'

    VISTA_KEY  = ENV.fetch('VISTA_KEY')  { 'ea83a702a7669520304be011258289fd' }
    VISTA_HOST = ENV.fetch('VISTA_HOST') { 'http://saluteim20174-rest.vistahost.com.br' }
    LIST_PATH  = '/usuarios/listar'
    PAGE_SIZE  = 50

    def self.call
      new.call
    end

    def call
      status = SyncStatusService.new
      status.mark_processing!(message: "Iniciando importação de corretores...", stats: empty_stats)

      page = 1
      total_processed = 0
      total_created = 0
      total_updated = 0
      total_errors = 0
      total_pages = nil

      loop do
        response = fetch_users(page)

        if response.blank? || (response['status'].present? && response['status'].to_i >= 400)
          status.mark_failed!(
            message: "Erro ao buscar página #{page}: #{response['message'] || response}",
            stats: build_stats(processed: total_processed, created: total_created, updated: total_updated, errors: total_errors + 1, page: page, total_pages: total_pages)
          )
          return
        end

        total_pages = response['paginas'].to_i
        users_data = response.except('total', 'paginas', 'pagina', 'quantidade')

        break if users_data.empty?

        users_data.each do |_, user_data|
          next unless user_data.is_a?(Hash)

          result = process_user(user_data)
          case result
          when :created then total_created += 1
          when :updated then total_updated += 1
          when :error   then total_errors  += 1
          end
          total_processed += 1 unless result == :skipped
        end

        progress = total_pages.positive? ? ((page.to_f / total_pages) * 100).to_i : 0
        status.update_progress!(
          progress: progress,
          message: "Página #{page} de #{total_pages} processada — #{total_processed} corretores até aqui",
          stats: build_stats(processed: total_processed, created: total_created, updated: total_updated, errors: total_errors, page: page, total_pages: total_pages)
        )

        break if page >= total_pages
        page += 1
      end

      status.mark_completed!(
        message: "Importação finalizada — #{total_created} criados, #{total_updated} atualizados, #{total_errors} erros",
        stats: build_stats(processed: total_processed, created: total_created, updated: total_updated, errors: total_errors, page: page, total_pages: total_pages)
      )
    rescue => e
      SyncStatusService.new.mark_failed!(message: "Exceção: #{e.message}", stats: {})
      raise
    end

    private

    # Mapeia as flags booleanas (Sim/Nao) do Vista para 1 Profile local.
    # A Vista permite acumular cargos (ex: Gerente + Corretor); escolhemos
    # o de maior autoridade segundo a ordem abaixo. Profile é criado on-demand
    # com permissions vazias — o admin ajusta em /admin/profiles depois.
    PROFILE_PRIORITY = %w[Diretor Gerente Administrativo Corretor].freeze

    def resolve_profile(data)
      name = PROFILE_PRIORITY.find { |flag| data[flag].to_s.casecmp("sim").zero? } || "Corretor"
      Profile.where("LOWER(name) = ?", name.downcase).first ||
        Profile.create!(name: name, permissions: {}, active: true)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[Vista Import] Falha ao criar Profile '#{name}': #{e.message}")
      nil
    end

    def empty_stats
      { processed: 0, created: 0, updated: 0, errors: 0, page: 0, total_pages: 0 }
    end

    def build_stats(**attrs)
      empty_stats.merge(attrs)
    end

    def fetch_users(page)
      # Fields verified via 'listarcampos' and manual testing
      fields = [
        'Codigo',
        'Nomecompleto',
        'E-mail', # Important: api uses hyphen
        'CRECI',
        'Celular',
        'Foto',
        'Observacoes',
        'Nascimento',
        'Cidade',
        'Sexo',
        'Inativo',
        'Atuaçãoemvenda',
        'Atuaçãoemlocação',
        # Flags booleanas de cargo (Sim/Nao). Usadas para mapear ao Profile.
        'Diretor',
        'Gerente',
        'Administrativo',
        'Corretor'
      ]
      
      query = {
        fields: fields,
        paginacao: {
          pagina: page,
          quantidade: PAGE_SIZE
        }
      }

      url = URI.join(VISTA_HOST, LIST_PATH).to_s
      params = {
        key: VISTA_KEY,
        pesquisa: query.to_json,
        showtotal: 1
      }

      response = RestClient.get(url, { params: params, accept: :json })
      JSON.parse(response.body)
    rescue => e
      puts "Erro na requisição: #{e.message}"
      {}
    end

    def process_user(data)
      email = data['E-mail']
      return :skipped unless email.present?

      # Find by vista_id first to handle email changes, fallback to email
      user = AdminUser.find_by(vista_id: data['Codigo']) || AdminUser.find_or_initialize_by(email: email)
      is_new = user.new_record?

      user.vista_id = data['Codigo']
      user.name     = data['Nomecompleto'].presence || user.name
      user.creci    = data['CRECI']
      user.phone    = data['Celular']
      user.biography = data['Observacoes']
      user.city     = data['Cidade']
      user.active   = data['Inativo'] != 'Sim'
      
      # Assign Profile derivado das flags do Vista (Diretor > Gerente >
      # Administrativo > Corretor). Auto-cria o Profile se ele não existir.
      assigned_profile = resolve_profile(data)
      user.profile = assigned_profile if assigned_profile && user.profile.blank?
      
      if data['Nascimento'].present? && data['Nascimento'] != '0000-00-00'
        user.birth_date = Date.parse(data['Nascimento']) rescue nil
      end

      # Map Acting Type
      venda = data['Atuaçãoemvenda'] == 'Sim'
      locacao = data['Atuaçãoemlocação'] == 'Sim'

      user.acting_type = if venda && locacao
                           :both
                         elsif venda
                           :sales
                         elsif locacao
                           :rentals
                         else
                           :both # Fallback if neither is set, though unlikely for active agents
                         end

      # Set default password for new users
      if is_new
        user.password = SecureRandom.hex(8) 
        # Optional: Send email with instructions? For now just setting it.
      end

      # Handle Avatar
      if data['Foto'].present?
        attach_avatar(user, data['Foto'])
      end

      if user.save
        is_new ? :created : :updated
      else
        Rails.logger.warn("[Vista Import] Falha ao salvar #{email}: #{user.errors.full_messages.join(', ')}")
        :error
      end
    end

    def attach_avatar(user, url)
      return if avatar_available?(user)

      begin
        user.avatar.purge if user.avatar.attached?
        downloaded_image = URI.open(url)
        user.avatar.attach(io: downloaded_image, filename: "vista_avatar_#{user.vista_id}.jpg")
      rescue => e
        puts "\nErro ao baixar foto para #{user.email}: #{e.message}"
      end
    end

    def avatar_available?(user)
      return false unless user.avatar.attached?

      user.avatar.blob.open { true }
    rescue ActiveStorage::FileNotFoundError
      false
    end
  end
end
