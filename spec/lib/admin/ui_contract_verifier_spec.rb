require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/admin/ui_contract_verifier"

RSpec.describe Admin::UiContractVerifier do
  around do |example|
    Dir.mktmpdir do |dir|
      @tmp_root = dir
      example.run
    end
  end

  it "aceita uso das primitives sem Bootstrap residual" do
    write_file("app/views/admin/seo_settings/index.html.erb", <<~ERB)
      <%= ax_badge("Indexáveis 37", tone: :green) %>
      <div class="seo-settings-badge-grid"></div>
    ERB
    write_file("app/assets/stylesheets/admin_tailwind.css", <<~CSS)
      .seo-settings-badge-grid {
        display: flex;
        gap: 6px;
      }
    CSS

    verifier = described_class.new(root: @tmp_root)

    expect(verifier).to be_valid
    expect(verifier.violations).to be_empty
  end

  it "rejeita badge manual em area migrada" do
    write_file("app/views/admin/seo_settings/index.html.erb", <<~ERB)
      <span class="ax-badge ax-badge--green">Indexáveis 37</span>
    ERB
    write_file("app/assets/stylesheets/admin_tailwind.css", "")

    verifier = described_class.new(root: @tmp_root)

    expect(verifier.violations.map(&:rule)).to include("manual_ax_badge")
  end

  it "rejeita markup Bootstrap residual em area migrada" do
    write_file("app/views/admin/seo_dashboard/index.html.erb", <<~ERB)
      <div class="row">
        <div class="col-6">
          <input class="form-control">
        </div>
      </div>
    ERB
    write_file("app/assets/stylesheets/admin_tailwind.css", "")

    verifier = described_class.new(root: @tmp_root)

    expect(verifier.violations.map(&:rule)).to include("bootstrap_legacy_markup")
  end

  it "rejeita override local de primitive compartilhada" do
    write_file("app/views/admin/seo_settings/index.html.erb", "<%= ax_badge('Inventário', tone: :blue) %>")
    write_file("app/assets/stylesheets/admin_tailwind.css", <<~CSS)
      .seo-settings-badge-grid .ax-badge {
        font-weight: 700;
      }
    CSS

    verifier = described_class.new(root: @tmp_root)

    expect(verifier.violations.map(&:rule)).to include("screen_specific_primitive_override")
  end

  it "aceita contrato compartilhado do WhatsApp" do
    write_valid_whatsapp_contract
    write_file("app/assets/stylesheets/admin_tailwind.css", "")

    verifier = described_class.new(root: @tmp_root)

    expect(verifier).to be_valid
  end

  it "rejeita polling visual automatico no WhatsApp" do
    write_valid_whatsapp_contract
    write_file("app/assets/stylesheets/admin_tailwind.css", "")
    write_file("app/javascript/controllers/wa_thread_controller.js", <<~JS)
      export default class {
        connect() {
          setInterval(() => this.poll(), 3000)
        }
      }
    JS

    verifier = described_class.new(root: @tmp_root)

    expect(verifier.violations.map(&:rule)).to include("whatsapp_no_interval_polling", "whatsapp_no_connect_polling")
  end

  it "rejeita endpoint e metodo de polling HTTP na thread WhatsApp" do
    write_valid_whatsapp_contract
    write_file("app/assets/stylesheets/admin_tailwind.css", "")
    write_file("app/views/admin/whatsapp_inbox/_thread_workspace.html.erb", <<~ERB)
      <div data-controller="wa-thread fancybox-gallery" data-wa-thread-url-value="/admin/atendimento/whatsapp/5/messages"></div>
    ERB
    write_file("app/javascript/controllers/wa_thread_controller.js", <<~JS)
      export default class {
        async poll() {
          return fetch(this.urlValue)
        }
      }
    JS

    verifier = described_class.new(root: @tmp_root)

    expect(verifier.violations.map(&:rule)).to include("whatsapp_no_messages_polling_endpoint", "whatsapp_no_poll_method")
  end

  it "rejeita quando inbox WhatsApp deixa de usar o composer compartilhado" do
    write_valid_whatsapp_contract
    write_file("app/assets/stylesheets/admin_tailwind.css", "")
    write_file("app/views/admin/whatsapp_inbox/index.html.erb", <<~ERB)
      <%= render "thread_workspace" %>
      <form class="wa-inbox-composer"></form>
    ERB

    verifier = described_class.new(root: @tmp_root)

    expect(verifier.violations.map(&:rule)).to include("whatsapp_shared_composer")
  end

  it "rejeita autoplay ou preload indevido em midia do WhatsApp" do
    write_valid_whatsapp_contract
    write_file("app/assets/stylesheets/admin_tailwind.css", "")
    write_file("app/views/admin/whatsapp_inbox/_message_bubble.html.erb", <<~ERB)
      <a data-fancybox-type="inline"></a>
      <div data-controller="wa-audio-preview"></div>
      <audio data-src="<%= media_url %>" preload="auto" autoplay></audio>
    ERB

    verifier = described_class.new(root: @tmp_root)

    expect(verifier.violations.map(&:rule)).to include("whatsapp_audio_no_preload", "whatsapp_media_no_autoplay")
  end

  it "rejeita visualizador inline paralelo no controller do Fancybox" do
    write_valid_whatsapp_contract
    write_file("app/assets/stylesheets/admin_tailwind.css", "")
    write_file("app/javascript/controllers/fancybox_gallery_controller.js", <<~JS)
      export default class {
        openInlineViewer() {
          document.body.insertAdjacentHTML("beforeend", '<div class="wa-inline-viewer"></div>')
        }
      }
    JS

    verifier = described_class.new(root: @tmp_root)

    expect(verifier.violations.map(&:rule)).to include("whatsapp_use_fancybox_modal")
  end

  def write_file(path, content)
    absolute_path = File.join(@tmp_root, path)
    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.write(absolute_path, content)
  end

  def write_valid_whatsapp_contract
    write_file("app/views/admin/whatsapp_inbox/index.html.erb", <<~ERB)
      <%= render "thread_workspace" %>
      <%= render "admin/shared/ui/whatsapp_composer" %>
    ERB
    write_file("app/views/admin/whatsapp_inbox/_thread_workspace.html.erb", <<~ERB)
      <div data-controller="wa-thread fancybox-gallery">
        <%= render "admin/whatsapp_inbox/message_bubble" %>
      </div>
    ERB
    write_file("app/views/admin/whatsapp_inbox/_message_bubble.html.erb", <<~ERB)
      <a data-fancybox-type="inline"></a>
      <div data-controller="wa-audio-preview"></div>
      <audio data-src="<%= media_url %>" preload="none"></audio>
    ERB
    write_file("app/views/admin/shared/ui/_lead_whatsapp_panel.html.erb", <<~ERB)
      <%= render "admin/whatsapp_inbox/thread_workspace" %>
      <%= render "admin/shared/ui/whatsapp_composer" %>
    ERB
    write_file("app/views/admin/shared/ui/_whatsapp_composer.html.erb", <<~ERB)
      <%= form_with data: { controller: "wa-composer" } do %>
      <% end %>
    ERB
    write_file("app/javascript/controllers/wa_thread_controller.js", <<~JS)
      export default class {
        connect() {
          this.connectCable()
        }

        poll() {}
      }
    JS
    write_file("app/javascript/controllers/wa_audio_preview_controller.js", <<~JS)
      export default class {
        connect() {
          this.audioTarget.autoplay = false
        }
      }
    JS
    write_file("app/javascript/controllers/fancybox_gallery_controller.js", <<~JS)
      export default class {}
    JS
  end
end
