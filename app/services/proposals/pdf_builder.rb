module Proposals
  # Gera o PDF da proposta comercial usando Prawn (puro Ruby, sem binário de sistema).
  class PdfBuilder
    BRAND = "0F766E".freeze
    INK = "1F2937".freeze
    MUTED = "6B7280".freeze

    def initialize(proposal)
      @proposal = proposal
      @lead = proposal.lead
      @habitation = proposal.habitation
    end

    def render
      require "prawn"
      require "prawn/table"
      Prawn::Fonts::AFM.hide_m17n_warning = true if defined?(Prawn::Fonts::AFM)
      pdf = Prawn::Document.new(page_size: "A4", margin: [48, 48, 48, 48])

      header(pdf)
      property_block(pdf)
      values_block(pdf)
      conditions_block(pdf)
      footer(pdf)

      pdf.render
    end

    private

    def header(pdf)
      pdf.fill_color BRAND
      pdf.text "Proposta Comercial", size: 22, style: :bold
      pdf.fill_color MUTED
      pdf.text "Código #{@proposal.public_token} · #{I18n.l(@proposal.created_at.to_date, format: :long) rescue @proposal.created_at.strftime('%d/%m/%Y')}", size: 9
      pdf.move_down 6
      pdf.stroke_color "E5E7EB"
      pdf.stroke_horizontal_rule
      pdf.move_down 16
    end

    def property_block(pdf)
      pdf.fill_color INK
      if @habitation
        pdf.text safe(@habitation.try(:display_title).presence || "Imóvel"), size: 14, style: :bold
        pdf.fill_color MUTED
        location = [@habitation.try(:bairro), @habitation.try(:cidade)].compact.join(", ")
        pdf.text safe([("Ref. #{@habitation.try(:codigo)}" if @habitation.try(:codigo)), location].compact.join(" · ")), size: 10
      else
        pdf.text safe(@proposal.title.presence || "Proposta"), size: 14, style: :bold
      end
      pdf.move_down 14
    end

    def values_block(pdf)
      rows = [["Descrição", "Valor"]]
      rows << ["Valor da proposta", brl(@proposal.valor)] if @proposal.valor_cents.to_i.positive?
      rows << ["Entrada", brl(@proposal.entrada)] if @proposal.entrada_cents.to_i.positive?
      return if rows.size == 1

      pdf.table(rows, width: pdf.bounds.width, cell_style: { borders: [:bottom], border_color: "E5E7EB", padding: [8, 6] }) do |t|
        t.row(0).font_style = :bold
        t.row(0).background_color = "F3F4F6"
        t.column(1).align = :right
      end
      pdf.move_down 16
    end

    def conditions_block(pdf)
      return if @proposal.condicoes.blank?
      pdf.fill_color INK
      pdf.text "Condições", size: 12, style: :bold
      pdf.move_down 4
      pdf.fill_color "374151"
      pdf.text safe(@proposal.condicoes.to_s), size: 10, leading: 3
      pdf.move_down 16
    end

    def footer(pdf)
      pdf.move_down 8
      pdf.stroke_color "E5E7EB"
      pdf.stroke_horizontal_rule
      pdf.move_down 8
      pdf.fill_color MUTED
      validity = @proposal.validade.present? ? "Válida até #{@proposal.validade.strftime('%d/%m/%Y')}." : nil
      broker = @proposal.admin_user&.name
      pdf.text safe([validity, ("Corretor responsável: #{broker}" if broker)].compact.join(" ")), size: 9
    end

    def brl(value)
      "R$ %0.2f" % value.to_f
    rescue
      "R$ 0,00"
    end

    # Remove caracteres fora do Windows-1252 para não quebrar as fontes AFM do Prawn.
    def safe(str)
      str.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "").encode("UTF-8")
    end
  end
end
