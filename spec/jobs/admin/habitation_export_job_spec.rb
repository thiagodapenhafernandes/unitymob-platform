require "rails_helper"

RSpec.describe Admin::HabitationExportJob, type: :job do
  let(:user) { AdminUser.create!(email: "exp#{SecureRandom.hex(3)}@x.com", password: "password123", name: "Exp", role: :admin) }

  it "gera o CSV, anexa o arquivo e marca como completed (progress 100)" do
    h1 = create(:habitation, codigo: "JOB1")
    h2 = create(:habitation, codigo: "JOB2")
    export = user.habitation_exports.create!(
      status: "pending", filename: "t.csv",
      fields: %w[codigo categoria valor_venda], source_ids: [h1.id, h2.id],
      col_sep: ";", record_count: 2
    )

    described_class.perform_now(export.id)
    export.reload

    expect(export.status).to eq("completed")
    expect(export.progress).to eq(100)
    expect(export.file).to be_attached

    csv = export.file.download
    expect(csv.lines.first.strip).to eq("Referencia;Categoria;Valor venda")
    expect(csv.lines.size).to eq(3) # header + 2 imóveis
  end

  it "marca como failed quando algo quebra" do
    export = user.habitation_exports.create!(status: "pending", filename: "t.csv",
                                             fields: %w[codigo], source_ids: [1], record_count: 1)
    allow(Habitations::CsvExporter).to receive(:header_row).and_raise("boom")

    expect { described_class.perform_now(export.id) }.to raise_error("boom")
    expect(export.reload.status).to eq("failed")
    expect(export.error_message).to include("boom")
  end

  describe Habitations::CsvExporter do
    it "monta a linha com os campos formatados (proprietario sem máscara)" do
      h = create(:habitation, codigo: "C9")
      row = described_class.row(h, %w[codigo categoria])
      expect(row.first).to eq("C9")
      expect(described_class.header_row(%w[codigo])).to eq(["Referencia"])
    end
  end
end
