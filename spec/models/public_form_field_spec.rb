require "rails_helper"

RSpec.describe PublicFormField do
  def field(type = "text", config = {})
    described_class.new(field_type: type, name: "campo", label: "Campo", config: config)
  end

  describe "largura no modal" do
    it "automática: texto longo, escolhas e anexo em linha inteira; o resto em meia coluna" do
      expect(%w[textarea radio checkbox file].map { |type| field(type).effective_width }).to all(eq("full"))
      expect(%w[text email tel select number].map { |type| field(type).effective_width }).to all(eq("half"))
    end

    it "meia e inteira valem sobre o padrão do tipo; valor desconhecido volta para automática" do
      expect(field("textarea", "width" => "half").effective_width).to eq("half")
      expect(field("text", "width" => "full").effective_width).to eq("full")
      expect(field("text", "width" => "enorme").effective_width).to eq("half")
    end

    it "não guarda 'auto' nem valor inválido na config" do
      auto = field("text", "width" => "auto")
      auto.valid?
      expect(auto.config).not_to include("width")

      full = field("text", "width" => "full")
      full.valid?
      expect(full.config["width"]).to eq("full")
    end
  end

  describe "máscara" do
    it "converte o formato em regex (campo e servidor usam a mesma)" do
      creci = field("text", "mask" => "00000-A")
      expect(creci.mask_pattern_source).to eq('\d\d\d\d\d-[A-Za-z]')
      expect(creci.mask_match?("12345-F")).to eq(true)
      expect(creci.mask_match?("1234-F")).to eq(false)
      expect(creci.mask_match?("12345-1")).to eq(false)

      phone = field("tel", "mask" => "(00) 00000-0000")
      expect(phone.mask_match?("(47) 99999-0000")).to eq(true)
      expect(phone.mask_match?("47999990000")).to eq(false)
    end

    it "tipo Moeda usa dinheiro sozinho; uma máscara própria vale mais" do
      currency = field("currency")
      expect(currency.mask_value).to eq("money")
      expect(currency.mask_hint).to eq("R$ 0,00")
      expect(currency.mask_match?("R$ 1.234,56")).to eq(true)
      expect(currency.mask_match?("R$ 12,5")).to eq(false)
      expect(field("currency", "mask" => "000.000").mask_value).to eq("000.000")
    end

    it "só vale para texto, número, telefone e moeda, e some quando o tipo muda para outro" do
      expect(field("email", "mask" => "00").mask?).to eq(false)
      moved = field("select", "mask" => "00-0000")
      moved.valid?
      expect(moved.config).not_to include("mask")
    end

    it "recusa caracteres fora de 0 A * e símbolos de formatação (nada livre vira HTML)" do
      invalid = field("text", "mask" => "<script>")
      expect(invalid).not_to be_valid
      expect(invalid.errors.full_messages.join).to include("Máscara")

      too_long = field("text", "mask" => "0" * 41).tap(&:valid?)
      expect(too_long.errors[:mask]).to be_present
      expect(field("text", "mask" => "0000").tap(&:valid?).errors[:mask]).to be_empty
    end

    it "teclado numérico só quando o formato tem apenas dígitos e símbolos" do
      expect(field("text", "mask" => "(00) 0000-0000").mask_digits_only?).to eq(true)
      expect(field("text", "mask" => "00000-A").mask_digits_only?).to eq(false)
      expect(field("currency").mask_digits_only?).to eq(true)
    end
  end

  it "atribuição parcial de config preserva as demais chaves" do
    hidden = field("hidden", "value" => "origem-site")
    hidden.config = { "width" => "full" }

    expect(hidden.config).to include("value" => "origem-site", "width" => "full")
  end
end
