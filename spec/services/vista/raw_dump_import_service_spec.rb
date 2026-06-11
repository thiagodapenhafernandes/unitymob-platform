require "rails_helper"
require "tmpdir"

RSpec.describe Vista::RawDumpImportService do
  around do |example|
    Dir.mktmpdir do |dir|
      @dump_dir = Pathname.new(dir)
      example.run
    end
  end

  it "reads multiline values and preserves the complete payload in dry run" do
    write_sql(
      "CADIMO",
      <<~SQL
        INSERT INTO `CADIMO` (`CODIGO`, `CODIGO_C`, `CODIGO_M`, `OBS`) VALUES
        ('1001','2001','3001','linha um
        linha dois com vírgula, acento e \\'aspas\\''),
        ('1002','2002','3002','texto simples');
      SQL
    )

    result = described_class.new(dump_dir: @dump_dir, dry_run: true).call

    expect(result.total_rows).to eq(2)
    expect(result.tables["CADIMO"]).to include(rows: 2, columns: 4)
    expect(result.errors).to be_empty
  end

  it "stores link keys for property, client and broker references" do
    write_sql(
      "CDIMAG",
      <<~SQL
        INSERT INTO `CDIMAG` (`NUMERO`, `CODIGO_O`, `CODIGO_D`, `COMISSAO`) VALUES
        ('10','1001','3001','5.00');
      SQL
    )

    result = described_class.new(dump_dir: @dump_dir, dry_run: false).call
    record = result.batch.vista_raw_records.find_by!(table_name: "CDIMAG")

    expect(record.source_key).to eq("10:1001:3001")
    expect(record.codigo_imovel).to eq("1001")
    expect(record.codigo_corretor).to eq("3001")
    expect(record.payload).to include("COMISSAO" => "5.00")
  end

  def write_sql(table, content)
    @dump_dir.join("#{table}.sql").write(content)
  end
end
