module CommercialContracts
  class PdfBuilder
    BRAND = "365F8F".freeze
    INK = "1F2937".freeze
    MUTED = "64748B".freeze
    BORDER = "E5E7EB".freeze

    def initialize(proposal, acceptance: nil, kind: :contract)
      @proposal = proposal
      @acceptance = acceptance || proposal.acceptance
      @terms = proposal.terms_version
      @kind = kind.to_sym
    end

    def render
      require "prawn"
      require "prawn/table"
      Prawn::Fonts::AFM.hide_m17n_warning = true if defined?(Prawn::Fonts::AFM)

      pdf = Prawn::Document.new(page_size: "A4", margin: [42, 46, 42, 46])
      @kind == :certificate ? certificate(pdf) : contract(pdf)
      pdf.render
    end

    private

    attr_reader :proposal, :acceptance, :terms

    def contract(pdf)
      header(pdf, "Contrato de Prestação de Serviço", proposal.public_token)
      section_title(pdf, "Contratante")
      key_values(pdf, [
        ["Razão social", proposal.legal_business_name],
        ["Nome fantasia", proposal.trade_name.presence || "-"],
        ["CNPJ", format_cnpj(proposal.cnpj)],
        ["E-mail", proposal.client_email.presence || "-"],
        ["Telefone", proposal.client_phone.presence || "-"]
      ])

      section_title(pdf, "Plano contratado")
      key_values(pdf, [
        ["Plano", proposal.plan_name],
        ["Implantação", proposal.setup_fee_cents.to_i.positive? ? money(proposal.setup_fee_cents) : "Sem cobrança inicial"],
        ["Início previsto", proposal.starts_on ? I18n.l(proposal.starts_on) : "Após confirmação operacional"],
        ["Prazo mínimo", proposal.minimum_term_months.to_i.positive? ? "#{proposal.minimum_term_months} meses" : "Sem fidelidade mínima"]
      ])

      section_title(pdf, "Escopo")
      paragraph(pdf, proposal.scope_summary)
      section_title(pdf, "Custos de terceiros")
      paragraph(pdf, proposal.external_costs_note)
      section_title(pdf, "Condições comerciais")
      paragraph(pdf, proposal.billing_notes.presence || "Cobrança mensal recorrente conforme proposta aceita eletronicamente.")
      section_title(pdf, terms.title)
      paragraph(pdf, terms.body)

      if acceptance
        section_title(pdf, "Aceite eletrônico")
        key_values(pdf, [
          ["Representante", acceptance.representative_name],
          ["CPF", format_cpf(acceptance.representative_cpf)],
          ["Cargo", acceptance.representative_role],
          ["E-mail confirmado", acceptance.representative_email],
          ["Data/hora", I18n.l(acceptance.accepted_at, format: :long)],
          ["IP", acceptance.ip_address],
          ["Hash dos termos", acceptance.terms_hash],
          ["Hash da proposta", acceptance.proposal_hash]
        ])
      end

      footer(pdf)
    end

    def certificate(pdf)
      header(pdf, "Certificado de Aceite Eletrônico", acceptance&.acceptance_token || proposal.public_token)
      paragraph(pdf, "Este certificado registra as evidências técnicas do aceite eletrônico da contratação Unitymob.")
      key_values(pdf, [
        ["Proposta", proposal.public_token],
        ["Status", proposal.status_label],
        ["Contratante", proposal.legal_business_name],
        ["CNPJ", format_cnpj(proposal.cnpj)],
        ["Representante", acceptance&.representative_name],
        ["CPF", format_cpf(acceptance&.representative_cpf)],
        ["Cargo", acceptance&.representative_role],
        ["E-mail", acceptance&.representative_email],
        ["Aceito em", acceptance&.accepted_at ? I18n.l(acceptance.accepted_at, format: :long) : "-"],
        ["IP", acceptance&.ip_address],
        ["User-agent", acceptance&.user_agent],
        ["Versão dos termos", terms.version],
        ["Hash dos termos", acceptance&.terms_hash || terms.document_hash],
        ["Hash do contrato", acceptance&.proposal_hash],
        ["Hash de confirmação OTP", acceptance&.otp_confirmation_hash]
      ])
      section_title(pdf, "Evidências registradas")
      paragraph(pdf, JSON.pretty_generate(acceptance&.evidence || {}))
      footer(pdf)
    end

    def header(pdf, title, token)
      pdf.fill_color BRAND
      pdf.text title, size: 21, style: :bold
      pdf.fill_color MUTED
      pdf.text "Unitymob · #{token} · #{I18n.l(Time.current, format: :long)}", size: 9
      pdf.move_down 9
      pdf.stroke_color BORDER
      pdf.stroke_horizontal_rule
      pdf.move_down 14
    end

    def section_title(pdf, title)
      pdf.move_down 10
      pdf.fill_color INK
      pdf.text title.to_s, size: 12, style: :bold
      pdf.move_down 5
    end

    def key_values(pdf, rows)
      pdf.table(rows.map { |label, value| [label.to_s, safe(value)] },
                width: pdf.bounds.width,
                cell_style: { borders: [:bottom], border_color: BORDER, padding: [6, 5], size: 9 }) do |table|
        table.column(0).font_style = :bold
        table.column(0).text_color = INK
        table.column(0).width = 132
        table.column(1).text_color = "374151"
      end
    end

    def paragraph(pdf, text)
      pdf.fill_color "374151"
      pdf.text safe(text), size: 9.5, leading: 3
    end

    def footer(pdf)
      pdf.move_down 14
      pdf.stroke_color BORDER
      pdf.stroke_horizontal_rule
      pdf.move_down 7
      pdf.fill_color MUTED
      pdf.text "Documento gerado automaticamente pela Unitymob. As evidências ficam vinculadas à proposta e ao tenant.", size: 8
    end

    def money(cents)
      "R$ #{format('%.2f', cents.to_i / 100.0).tr('.', ',')}"
    end

    def format_cnpj(value)
      digits = value.to_s.gsub(/\D/, "")
      return value.to_s if digits.length != 14

      digits.gsub(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, "\\1.\\2.\\3/\\4-\\5")
    end

    def format_cpf(value)
      digits = value.to_s.gsub(/\D/, "")
      return value.to_s if digits.length != 11

      digits.gsub(/(\d{3})(\d{3})(\d{3})(\d{2})/, "\\1.\\2.\\3-\\4")
    end

    def safe(value)
      value.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "")
    end
  end
end
