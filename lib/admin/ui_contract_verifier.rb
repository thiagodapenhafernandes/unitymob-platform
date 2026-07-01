module Admin
  class UiContractVerifier
    Violation = Struct.new(:path, :line, :rule, :message, keyword_init: true) do
      def to_s
        "#{path}:#{line} [#{rule}] #{message}"
      end
    end

    DEFAULT_VIEW_GLOBS = [
      "app/views/admin/seo_dashboard/**/*.erb",
      "app/views/admin/seo_settings/**/*.erb",
      "app/views/admin/whatsapp_inbox/**/*.erb",
      "app/views/admin/whatsapp_campaigns/**/*.erb"
    ].freeze

    DEFAULT_CSS_GLOBS = [
      "app/assets/stylesheets/admin_tailwind.css"
    ].freeze

    DEFAULT_JS_GLOBS = [
      "app/javascript/controllers/wa_thread_controller.js",
      "app/javascript/controllers/wa_audio_preview_controller.js",
      "app/javascript/controllers/fancybox_gallery_controller.js"
    ].freeze

    FORBIDDEN_BOOTSTRAP_CLASS_PATTERNS = [
      /^row$/,
      /^col(?:-(?:auto|\d+|sm|md|lg|xl|xxl)(?:-\d+)?)?$/,
      /^form-group$/,
      /^card(?:-(?:header|body|footer|title|subtitle|text|img(?:-top|-bottom)?|link))?$/,
      /^badge(?:-.+)?$/,
      /^btn(?:-.+)?$/,
      /^form-control$/
    ].freeze

    WHATSAPP_CONTRACT_FILES = {
      index: "app/views/admin/whatsapp_inbox/index.html.erb",
      thread_workspace: "app/views/admin/whatsapp_inbox/_thread_workspace.html.erb",
      message_bubble: "app/views/admin/whatsapp_inbox/_message_bubble.html.erb",
      lead_panel: "app/views/admin/shared/ui/_lead_whatsapp_panel.html.erb",
      composer: "app/views/admin/shared/ui/_whatsapp_composer.html.erb",
      thread_controller: "app/javascript/controllers/wa_thread_controller.js",
      audio_controller: "app/javascript/controllers/wa_audio_preview_controller.js",
      fancybox_controller: "app/javascript/controllers/fancybox_gallery_controller.js"
    }.freeze

    def initialize(root: Rails.root.to_s, view_globs: DEFAULT_VIEW_GLOBS, css_globs: DEFAULT_CSS_GLOBS, js_globs: DEFAULT_JS_GLOBS)
      @root = root
      @view_globs = Array(view_globs)
      @css_globs = Array(css_globs)
      @js_globs = Array(js_globs)
    end

    def violations
      @violations ||= scan_views + scan_css + scan_js + scan_whatsapp_contract
    end

    def valid?
      violations.empty?
    end

    private

    attr_reader :root, :view_globs, :css_globs, :js_globs

    def scan_views
      view_files.flat_map do |file|
        scan_file(file) do |line, line_number, relative_path|
          [
            manual_badge_violation(line, line_number, relative_path),
            bootstrap_legacy_violation(line, line_number, relative_path)
          ].compact
        end
      end
    end

    def scan_css
      css_files.flat_map do |file|
        scan_file(file) do |line, line_number, relative_path|
          local_primitive_override_violation(line, line_number, relative_path)
        end
      end
    end

    def scan_js
      js_files.flat_map do |file|
        scan_file(file) do |line, line_number, relative_path|
          whatsapp_auto_polling_violation(line, line_number, relative_path)
        end
      end
    end

    def scan_whatsapp_contract
      return [] unless whatsapp_contract_enabled?

      [
        require_content(:index, 'render "thread_workspace"', "whatsapp_shared_thread", "Inbox WhatsApp deve renderizar o workspace compartilhado da conversa."),
        require_content(:index, 'render "admin/shared/ui/whatsapp_composer"', "whatsapp_shared_composer", "Inbox WhatsApp deve usar o composer compartilhado."),
        require_content(:thread_workspace, 'data-controller="wa-thread fancybox-gallery"', "whatsapp_thread_gallery_controller", "Thread WhatsApp deve conectar `wa-thread` e `fancybox-gallery` no mesmo root."),
        require_content(:message_bubble, 'data-fancybox-type="inline"', "whatsapp_inline_media_viewer", "Mídias da conversa devem abrir no visualizador inline, sem navegação de página."),
        require_content(:message_bubble, 'data-controller="wa-audio-preview"', "whatsapp_audio_preview_component", "Áudio da conversa deve usar o componente `wa-audio-preview`."),
        require_content(:message_bubble, 'data-src="<%= media_url %>"', "whatsapp_audio_lazy_source", "Áudio não deve carregar src no HTML inicial; use `data-src` e carregamento explícito."),
        require_content(:message_bubble, 'preload="none"', "whatsapp_audio_no_preload", "Áudio da timeline deve usar `preload=\"none\"`."),
        forbid_content(:message_bubble, "autoplay", "whatsapp_media_no_autoplay", "Mídias da timeline não podem usar autoplay."),
        forbid_content(:thread_workspace, "data-wa-thread-url-value", "whatsapp_no_messages_polling_endpoint", "Thread WhatsApp não deve expor endpoint `/messages` para polling visual; use ActionCable."),
        require_content(:lead_panel, 'render "admin/whatsapp_inbox/thread_workspace"', "whatsapp_lead_panel_shared_thread", "Bloco WhatsApp do lead deve reutilizar o workspace compartilhado."),
        require_content(:lead_panel, 'render "admin/shared/ui/whatsapp_composer"', "whatsapp_lead_panel_shared_composer", "Bloco WhatsApp do lead deve reutilizar o composer compartilhado."),
        forbid_content(:lead_panel, "Abrir inbox", "whatsapp_redundant_action", "Ação redundante `Abrir inbox` não deve voltar; a fila/thread já resolvem seleção."),
        forbid_content(:lead_panel, "Abrir WhatsApp", "whatsapp_redundant_action", "Ação redundante `Abrir WhatsApp` não deve voltar; use tela dedicada quando necessário."),
        forbid_content(:thread_controller, "async poll", "whatsapp_no_poll_method", "`wa-thread` não deve manter método de polling HTTP; ActionCable é o caminho principal."),
        forbid_connect_call(:thread_controller, /\bpoll\s*\(/, "whatsapp_no_connect_polling", "`wa-thread` não deve iniciar polling no connect; ActionCable é o caminho principal."),
        forbid_content(:audio_controller, "new Audio", "whatsapp_audio_no_probe", "Preview de áudio não deve criar player paralelo para pré-carregar metadados."),
        forbid_content(:audio_controller, "autoplay = true", "whatsapp_audio_no_autoplay", "Preview de áudio não pode ativar autoplay."),
        forbid_content(:fancybox_controller, "openInlineViewer", "whatsapp_use_fancybox_modal", "Mídias WhatsApp devem abrir pelo Fancybox real, não por visualizador inline paralelo."),
        forbid_content(:fancybox_controller, "wa-inline-viewer", "whatsapp_use_fancybox_modal", "Mídias WhatsApp devem abrir pelo Fancybox real, não por visualizador inline paralelo.")
      ].flatten.compact
    end

    def scan_file(file)
      relative_path = relative_path_for(file)

      File.readlines(file, chomp: true).flat_map.with_index(1) do |line, line_number|
        normalize_result(yield(line, line_number, relative_path))
      end
    end

    def manual_badge_violation(line, line_number, relative_path)
      return unless line.match?(/<span\b[^>]*class=["'][^"']*\bax-badge\b/i)

      Violation.new(
        path: relative_path,
        line: line_number,
        rule: "manual_ax_badge",
        message: "Badge manual em area migrada. Use `ax_badge` em vez de `<span class=\"ax-badge ...\">`."
      )
    end

    def bootstrap_legacy_violation(line, line_number, relative_path)
      extract_class_tokens(line).each do |token|
        next unless forbidden_bootstrap_class?(token)

        return Violation.new(
          path: relative_path,
          line: line_number,
          rule: "bootstrap_legacy_markup",
          message: "Classe Bootstrap residual `#{token}` em area migrada. Promova para primitive `ax-*` ou substitua pelo componente compartilhado."
        )
      end

      nil
    end

    def local_primitive_override_violation(line, line_number, relative_path)
      return unless line.match?(/(?:seo|whatsapp-campaign)[\w-]*.*ax-badge|ax-badge.*(?:seo|whatsapp-campaign)[\w-]*/)

      Violation.new(
        path: relative_path,
        line: line_number,
        rule: "screen_specific_primitive_override",
        message: "Override local de `.ax-badge` encontrado. Ajuste a primitive compartilhada em vez de corrigir por tela."
      )
    end

    def whatsapp_auto_polling_violation(line, line_number, relative_path)
      return unless relative_path.end_with?("wa_thread_controller.js")
      return unless line.match?(/\bsetInterval\s*\(/)

      Violation.new(
        path: relative_path,
        line: line_number,
        rule: "whatsapp_no_interval_polling",
        message: "Inbox WhatsApp nao deve usar polling visual com setInterval; use ActionCable e fallback de reconexao sem piscar UI."
      )
    end

    def require_content(key, needle, rule, message)
      content = whatsapp_file_content(key)
      return if content.include?(needle)

      Violation.new(
        path: WHATSAPP_CONTRACT_FILES.fetch(key),
        line: 1,
        rule: rule,
        message: message
      )
    end

    def forbid_content(key, needle, rule, message)
      content = whatsapp_file_content(key)
      index = content.index(needle)
      return unless index

      Violation.new(
        path: WHATSAPP_CONTRACT_FILES.fetch(key),
        line: line_number_for(content, index),
        rule: rule,
        message: message
      )
    end

    def forbid_connect_call(key, pattern, rule, message)
      content = whatsapp_file_content(key)
      connect_body = method_body(content, "connect")
      return unless connect_body.match?(pattern)

      Violation.new(
        path: WHATSAPP_CONTRACT_FILES.fetch(key),
        line: line_number_for(content, content.index(connect_body).to_i),
        rule: rule,
        message: message
      )
    end

    def whatsapp_file_content(key)
      path = File.join(root, WHATSAPP_CONTRACT_FILES.fetch(key))
      return "" unless File.exist?(path)

      File.read(path)
    end

    def whatsapp_contract_enabled?
      WHATSAPP_CONTRACT_FILES.values.any? { |path| File.exist?(File.join(root, path)) }
    end

    def method_body(content, method_name)
      match = content.match(/^\s*#{Regexp.escape(method_name)}\s*\([^)]*\)\s*\{/)
      return "" unless match

      start_index = match.end(0)
      depth = 1
      index = start_index

      while index < content.length
        char = content[index]
        depth += 1 if char == "{"
        depth -= 1 if char == "}"
        return content[start_index...index] if depth.zero?

        index += 1
      end

      ""
    end

    def line_number_for(content, index)
      content[0...index].count("\n") + 1
    end

    def extract_class_tokens(line)
      line.scan(/class=["']([^"']+)["']/i)
          .flatten
          .flat_map { |value| value.split(/\s+/) }
    end

    def forbidden_bootstrap_class?(token)
      FORBIDDEN_BOOTSTRAP_CLASS_PATTERNS.any? { |pattern| pattern.match?(token) }
    end

    def normalize_result(result)
      return [] if result.nil?
      return result if result.is_a?(Array)

      [result]
    end

    def view_files
      expand_globs(view_globs)
    end

    def css_files
      expand_globs(css_globs)
    end

    def js_files
      expand_globs(js_globs)
    end

    def expand_globs(globs)
      globs.flat_map { |glob| Dir.glob(File.join(root, glob)) }.uniq.sort
    end

    def relative_path_for(file)
      file.delete_prefix("#{root}/")
    end
  end
end
