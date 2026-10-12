require "rails_helper"

RSpec.describe Reports::DashboardXlsxWriter do
  it "produz ZIP íntegro e XML válido com acentos, caracteres reservados e células vazias" do
    body = described_class.new.call([
      { style: :title, cells: ["Ação & <contato>", nil, "150,00"] },
      { style: :lead_body, cells: ["Cliente"] }
    ], sheet_name: "Corretores & campanhas")
    entries = {}
    offset = 0
    while body.byteslice(offset, 4).unpack1("V") == 0x04034b50
      header = body.byteslice(offset, 30).unpack("VvvvvvVVVvv")
      name = body.byteslice(offset + 30, header[9])
      content = body.byteslice(offset + 30 + header[9] + header[10], header[7])
      expect(Zlib.crc32(content)).to eq(header[6])
      expect(Nokogiri::XML(content) { |config| config.strict }).to be_present
      entries[name] = content
      offset += 30 + header[9] + header[10] + header[7]
    end
    expect(entries.size).to eq(8)
    sheet = Nokogiri::XML(entries.fetch("xl/worksheets/sheet1.xml"))
    expect(sheet.xpath('//*[local-name()="t"]').map(&:text)).to eq(["Ação & <contato>", "150,00", "Cliente"])
    expect(sheet.xpath('//*[local-name()="c" and @r="B1"]').first.children).to be_empty
    expect(entries.fetch("xl/workbook.xml")).to include("Corretores &amp; campanhas")
    expect(body.byteslice(-22, 4).unpack1("V")).to eq(0x06054b50)
  end
end
