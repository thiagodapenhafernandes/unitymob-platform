require "rails_helper"

RSpec.describe Admin::UiHelper, type: :helper do
  describe "#ax_icon" do
    it "oculta o glifo decorativo da árvore de acessibilidade por padrão" do
      document = Nokogiri::HTML.fragment(helper.ax_icon("calendar-event", class_name: "extra"))

      expect(document.at_css('i.bi.bi-calendar-event.extra[aria-hidden="true"]')).to be_present
    end

    it "permite expor um ícone quando o consumidor fornecer semântica própria" do
      document = Nokogiri::HTML.fragment(helper.ax_icon("info-circle", decorative: false))

      expect(document.at_css("i.bi-info-circle")["aria-hidden"]).to be_nil
    end
  end

  describe "#ax_badge" do
    it "renderiza a primitive de badge com tom, dot e classe adicional" do
      html = helper.ax_badge("Ativa", tone: :green, dot: true, class_name: "extra-class", data: { status_target: "badge" })

      expect(html).to include("ax-badge")
      expect(html).to include("ax-badge--green")
      expect(html).to include("ax-badge--dot")
      expect(html).to include("extra-class")
      expect(html).to include('data-status-target="badge"')
      expect(html).to include(">Ativa</span>")
    end
  end

  describe "#ax_status_list" do
    it "renderiza pares rótulo/estado com semântica de lista descritiva" do
      document = Nokogiri::HTML.fragment(
        helper.ax_status_list(
          label: "Diagnóstico",
          rows: [
            { label: "Canal", value: helper.ax_badge("Pronto", tone: :green) },
            { label: "Origem", value: "Ambiente" }
          ]
        )
      )

      list = document.at_css('dl.ax-status-list[aria-label="Diagnóstico"]')
      expect(list).to be_present
      expect(list.css(".ax-status-list__row").size).to eq(2)
      expect(list.css("dt").map(&:text)).to eq(["Canal", "Origem"])
      expect(list.at_css("dd .ax-badge--green").text).to eq("Pronto")
    end
  end

  describe "#ax_standalone_field" do
    it "renderiza campo sem model com label, atributos, hint e ação acoplada" do
      document = Nokogiri::HTML.fragment(
        helper.ax_standalone_field(
          name: "otp_code",
          id: "security_otp",
          label: "Código atual",
          inputmode: "numeric",
          autocomplete: "one-time-code",
          maxlength: 6,
          hint: "Use seis dígitos.",
          action: helper.button_tag("Validar", type: "submit")
        )
      )

      expect(document.at_css('label.ax-field-label[for="security_otp"]')).to be_present
      expect(document.at_css('input.ax-control[name="otp_code"][id="security_otp"][inputmode="numeric"][autocomplete="one-time-code"][maxlength="6"]')).to be_present
      expect(document.at_css(".ax-input-group > button").text).to eq("Validar")
      expect(document.at_css(".ax-field__hint").text).to eq("Use seis dígitos.")
    end


    it "renderiza textarea avulso preservando nome e atributos" do
      document = Nokogiri::HTML.fragment(
        helper.ax_standalone_field(
          name: "names",
          id: "alias_names",
          label: "Nomes alternativos",
          type: :textarea,
          value: "Reserva Parque",
          rows: 2
        )
      )

      expect(document.at_css('textarea.ax-control[name="names"][id="alias_names"][rows="2"]').text.strip).to eq("Reserva Parque")
      expect(document.at_css('input[name="names"]')).to be_nil
    end
  end

  describe "#ax_standalone_select_field" do
    it "renderiza select avulso com opção vazia e seleção preservada" do
      document = Nokogiri::HTML.fragment(
        helper.ax_standalone_select_field(
          name: "development_id",
          id: "development_id",
          label: "Empreendimento",
          choices: [["Reserva", 10], ["Parque", 20]],
          selected: 20,
          include_blank: "Selecione"
        )
      )

      select = document.at_css('select.ax-control[name="development_id"][id="development_id"]')
      expect(select.css("option").map(&:text)).to eq(["Selecione", "Reserva", "Parque"])
      expect(select.at_css('option[selected="selected"]')["value"]).to eq("20")
    end


    it "preserva grupos e atributos das opções" do
      document = Nokogiri::HTML.fragment(
        helper.ax_standalone_select_field(
          name: "access_profile_id",
          id: "access_profile_id",
          label: "Perfil",
          choices: {
            "Hierarquia" => [["Corretor", 10, { data: { axis: "vertical" } }]],
            "Funções" => [["Suporte", 20, { data: { axis: "horizontal", vertical_profile_id: 10 } }]]
          },
          selected: 20,
          grouped: true
        )
      )

      expect(document.css("optgroup").map { |group| group["label"] }).to eq(["Hierarquia", "Funções"])
      expect(document.at_css('option[value="10"][data-axis="vertical"]')).to be_present
      expect(document.at_css('option[value="20"][data-axis="horizontal"][data-vertical-profile-id="10"][selected="selected"]')).to be_present
    end
  end

  describe "#ax_text_field" do
    it "preserva os tipos semânticos solicitados pelo consumidor" do
      html = helper.form_with(url: "/tipos", scope: :sample) do |form|
        helper.safe_join([
          helper.ax_text_field(
            form: form,
            method: :email,
            label: "E-mail",
            type: :email,
            class_name: "field-head",
            label_meta: helper.tag.span("12/65", class: "field-counter")
          ),
          helper.ax_text_field(form: form, method: :url, label: "URL", type: :url),
          helper.ax_text_field(form: form, method: :secret, label: "Senha", type: :password),
          helper.ax_text_field(form: form, method: :amount, label: "Quantidade", type: :number),
          helper.ax_text_field(form: form, method: :scheduled_at, label: "Agendamento", type: :"datetime-local"),
          helper.ax_text_field(form: form, method: :notes, label: "Notas", type: :textarea)
        ])
      end
      document = Nokogiri::HTML.fragment(html)

      expect(document.at_css('input[type="email"][name="sample[email]"]')).to be_present
      expect(document.at_css('label.field-head[for="sample_email"] .field-counter')&.text).to eq("12/65")
      expect(document.at_css('input[type="url"][name="sample[url]"]')).to be_present
      expect(document.at_css('input[type="password"][name="sample[secret]"]')).to be_present
      expect(document.at_css('input[type="number"][name="sample[amount]"]')).to be_present
      expect(document.at_css('input[type="datetime-local"][name="sample[scheduled_at]"]')).to be_present
      expect(document.at_css('textarea[name="sample[notes]"]')).to be_present
    end
  end

  describe "#ax_number_field" do
    it "renderiza hint sem exigir um model no form builder" do
      html = helper.form_with(url: "/numeros", scope: :sample) do |form|
        helper.ax_number_field(
          form: form,
          method: :opacity,
          label: "Opacidade",
          hint: "Use um valor entre 0,0 e 1,0.",
          min: 0,
          max: 1,
          step: 0.1
        )
      end
      document = Nokogiri::HTML.fragment(html)

      expect(document.at_css('input[type="number"][name="sample[opacity]"][min="0"][max="1"][step="0.1"]')).to be_present
      expect(document.at_css(".ax-field__hint").text).to eq("Use um valor entre 0,0 e 1,0.")
    end
  end

  describe "#ax_range_field" do
    it "relaciona label, range e output preservando hooks do consumidor" do
      html = helper.form_with(url: "/faixas", scope: :sample) do |form|
        helper.ax_range_field(
          form: form,
          method: :opacity,
          label: "Opacidade",
          value: 65,
          suffix: "%",
          hint: "Ajuste a intensidade.",
          min: 10,
          max: 100,
          input_data: { preview_target: "input" },
          output_data: { preview_target: "value" }
        )
      end
      document = Nokogiri::HTML.fragment(html)

      expect(document.at_css('label[for="sample_opacity"]')).to be_present
      expect(document.at_css('input[type="range"][id="sample_opacity"][data-preview-target="input"]')).to be_present
      expect(document.at_css('output[for="sample_opacity"][data-preview-target="value"]').text).to eq("65%")
      expect(document.at_css(".ax-field__hint").text).to eq("Ajuste a intensidade.")
    end
  end

  describe "#ax_radio_group" do
    it "propaga hooks de interação para cada opção" do
      html = helper.form_with(url: "/opcoes", scope: :sample) do |form|
        helper.ax_radio_group(
          form: form,
          method: :position,
          label: "Posição",
          choices: [["Centro", "center"], ["Direita", "right"]],
          input_data: { action: "preview#update", preview_target: "position" }
        )
      end
      document = Nokogiri::HTML.fragment(html)

      expect(document.css('input[type="radio"][data-action="preview#update"][data-preview-target="position"]').size).to eq(2)
    end
  end


  describe "#ax_field_label" do
    it "renderiza texto neutro sem criar label órfão" do
      document = Nokogiri::HTML.fragment(helper.ax_field_label(nil, nil, text: "Período"))

      expect(document.at_css("span.ax-field-label .ax-field-label__text").text).to eq("Período")
      expect(document.at_css("label")).to be_nil
    end

    it "preserva label associado quando o destino é explícito" do
      document = Nokogiri::HTML.fragment(helper.ax_field_label(nil, nil, text: "Corretor", for: "agent_select"))

      expect(document.at_css('label.ax-field-label[for="agent_select"]')).to be_present
    end

    it "mantém o botão de ajuda fora do label associado" do
      document = Nokogiri::HTML.fragment(
        helper.ax_field_label(nil, nil, text: "Corretor", for: "agent_select", tooltip: "Selecione um corretor.")
      )

      wrapper = document.at_css(".ax-field-label-wrap")
      expect(wrapper.at_css('label[for="agent_select"]')).to be_present
      expect(wrapper.at_css('button.ax-field-label__info[data-controller="ax-tooltip"]')).to be_present
      expect(wrapper.at_css("label button")).to be_nil
    end
  end

  describe "#ax_progress" do
    it "fornece nome acessível mesmo sem label explícito" do
      document = Nokogiri::HTML.fragment(helper.ax_progress(value: 42.5))
      progress = document.at_css("progress.ax-progress__bar")

      expect(progress["value"]).to eq("42.5")
      expect(progress["max"]).to eq("100")
      expect(progress["aria-label"]).to eq("Progresso: 42.5%")
    end

    it "preserva label, data attributes e limita valores fora da faixa" do
      document = Nokogiri::HTML.fragment(
        helper.ax_progress(value: 180, tone: :green, label: "Sincronização", data: { sync_target: "progress" })
      )
      wrapper = document.at_css(".ax-progress.ax-progress--green")
      progress = wrapper.at_css("progress")

      expect(wrapper["title"]).to eq("Sincronização")
      expect(progress["value"]).to eq("100")
      expect(progress["aria-label"]).to eq("Sincronização")
      expect(progress["data-sync-target"]).to eq("progress")
    end
  end


  describe "#ax_panel" do
    it "renderiza título, ações e região do painel recolhível" do
      document = Nokogiri::HTML.fragment(
        helper.ax_panel(
          title: "Tema da plataforma",
          actions: helper.ax_badge("configuração"),
          collapsible: true,
          collapsed: true,
          collapse_id: "theme-panel"
        ) { "Conteúdo" }
      )
      panel = document.at_css('section.ax-panel.ax-panel--collapsible[aria-label="Tema da plataforma"]')

      expect(panel.at_css('button.ax-panel__trigger[aria-expanded="false"][aria-controls="theme-panel"]')).to be_present
      expect(panel.at_css('#theme-panel.ax-panel__body[role="region"][aria-label="Tema da plataforma"][hidden]')).to be_present
      expect(panel.at_css(".ax-panel__actions .ax-badge").text).to eq("configuração")
    end

    it "não ativa disclosure em um painel estático" do
      document = Nokogiri::HTML.fragment(helper.ax_panel(title: "Credenciais") { "Conteúdo" })
      panel = document.at_css("section.ax-panel")

      expect(panel["data-controller"]).to be_nil
      expect(panel.at_css(".ax-panel__trigger")).to be_nil
      expect(panel.at_css(".ax-panel__body").text.strip).to eq("Conteúdo")
    end
  end

  describe "#ax_board" do
    it "nomeia o quadro como região sem perder hooks do consumidor" do
      document = Nokogiri::HTML.fragment(
        helper.ax_board(label: "Funil comercial", class_name: "ax-leads-board", data: { controller: "lead-kanban" }) { "Colunas" }
      )
      board = document.at_css('.ax-board.ax-leads-board[role="region"][aria-label="Funil comercial"]')

      expect(board["data-controller"]).to eq("lead-kanban")
      expect(board.text.strip).to eq("Colunas")
    end

    it "nomeia a coluna e anuncia atualizações do contador" do
      document = Nokogiri::HTML.fragment(
        helper.ax_board_column(title: "Em atendimento", count: 3, count_data: { lead_kanban_count: "Em atendimento" }) { "Card" }
      )
      column = document.at_css('section.ax-board__column[aria-label="Em atendimento"]')
      count = column.at_css('.ax-board__col-count[aria-live="polite"][aria-atomic="true"]')

      expect(count["aria-label"]).to eq("3 itens em Em atendimento")
      expect(count["data-lead-kanban-count"]).to eq("Em atendimento")
      expect(column.at_css(".ax-board__col-body").text).to include("Card")
    end
  end

  describe "#ax_lead_label_chip" do
    let(:label_class) { Struct.new(:name, :color) }

    it "renderiza tom catalogado sem estilo inline" do
      document = Nokogiri::HTML.fragment(helper.ax_lead_label_chip(label_class.new("Prioridade", "green")))
      chip = document.at_css(".lead-label-chip.lead-label-chip--green")

      expect(chip.text).to eq("Prioridade")
      expect(chip["style"]).to be_nil
      expect(chip["data-label-color"]).to be_nil
    end

    it "expõe a cor customizada como dado para hidratação segura" do
      document = Nokogiri::HTML.fragment(helper.ax_lead_label_chip(label_class.new("VIP", "#7c3aed")))
      chip = document.at_css(".lead-label-chip.lead-label-chip--custom")

      expect(chip["data-label-color"]).to eq("#7c3aed")
      expect(chip["style"]).to be_nil
    end
  end

  describe "#ax_team_toggle" do
    before do
      helper.define_singleton_method(:team_available?) { |_resource| true }
      helper.define_singleton_method(:include_team?) { |_resource| true }
      allow(helper).to receive(:team_available?).with(:comercial).and_return(true)
      allow(helper).to receive(:request).and_return(
        instance_double(ActionDispatch::TestRequest, path: "/admin/tasks", query_parameters: { "q" => "visita", "page" => "3" })
      )
    end

    it "preserva filtros, remove a página e desliga a equipe quando marcado" do
      allow(helper).to receive(:include_team?).with(:comercial).and_return(true)
      document = Nokogiri::HTML.fragment(helper.ax_team_toggle(:comercial))
      toggle = document.at_css('a.ax-team-toggle[role="switch"]')

      expect(toggle["href"]).to eq("/admin/tasks?q=visita&team=0")
      expect(toggle["aria-checked"]).to eq("true")
      expect(toggle["aria-label"]).to eq("Não incluir registros da equipe")
      expect(toggle.at_css(".ax-toggle-chip__box .bi-people-fill")).to be_present
    end

    it "liga a equipe sem descartar os demais filtros" do
      allow(helper).to receive(:include_team?).with(:comercial).and_return(false)
      document = Nokogiri::HTML.fragment(helper.ax_team_toggle(:comercial))
      toggle = document.at_css("a.ax-team-toggle")

      expect(toggle["href"]).to eq("/admin/tasks?q=visita&team=1")
      expect(toggle["aria-checked"]).to eq("false")
      expect(toggle["aria-label"]).to eq("Incluir registros da equipe")
    end

    it "não expõe o recorte quando a equipe não está disponível" do
      allow(helper).to receive(:team_available?).with(:comercial).and_return(false)

      expect(helper.ax_team_toggle(:comercial)).to be_nil
    end
  end


  describe "#ax_form_section" do
    it "nomeia a seção e sua região recolhível pelo título" do
      document = Nokogiri::HTML.fragment(
        helper.ax_form_section(title: "Dados jurídicos", collapse_id: "legal-data", collapsed: true) { "Conteúdo" }
      )
      section = document.at_css('section.ax-form-section[aria-label="Dados jurídicos"]')

      expect(section.at_css('button[aria-label="Alternar seção Dados jurídicos"][aria-expanded="false"][aria-controls="legal-data"]')).to be_present
      expect(section.at_css('#legal-data.ax-form-section__body[role="region"][aria-label="Dados jurídicos"][hidden]')).to be_present
    end

    it "mantém seção estática sem disclosure artificial" do
      document = Nokogiri::HTML.fragment(helper.ax_form_section(title: "Mercado de atuação") { "Conteúdo" })
      section = document.at_css("section.ax-form-section")

      expect(section["data-controller"]).to be_nil
      expect(section.at_css(".ax-form-section__toggle")).to be_nil
      expect(section.at_css(".ax-form-section__body").text.strip).to eq("Conteúdo")
    end
  end
end
