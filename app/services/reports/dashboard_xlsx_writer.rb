module Reports
  class DashboardXlsxWriter
    COLUMN_WIDTHS = [26, 20, 20, 20, 42, 18, 18, 18].freeze

    def call(rows, sheet_name:)
      build_xlsx_package(
        "[Content_Types].xml" => dashboard_report_xlsx_content_types_xml,
        "_rels/.rels" => dashboard_report_xlsx_root_relationships_xml,
        "docProps/app.xml" => dashboard_report_xlsx_app_properties_xml,
        "docProps/core.xml" => dashboard_report_xlsx_core_properties_xml,
        "xl/workbook.xml" => dashboard_report_xlsx_workbook_xml(sheet_name),
        "xl/_rels/workbook.xml.rels" => dashboard_report_xlsx_workbook_relationships_xml,
        "xl/styles.xml" => dashboard_report_xlsx_styles_xml,
        "xl/worksheets/sheet1.xml" => dashboard_report_xlsx_sheet_xml(rows)
      )
    end

    private

    def dashboard_report_xlsx_sheet_xml(rows)
      last_column = xlsx_column_name(COLUMN_WIDTHS.size)
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <dimension ref="A1:#{last_column}#{rows.size}"/>
          <sheetViews><sheetView workbookViewId="0"><pane ySplit="3" topLeftCell="A4" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
          <sheetFormatPr defaultRowHeight="19"/>
          <cols>
            #{COLUMN_WIDTHS.each_with_index.map { |width, index| %(<col min="#{index + 1}" max="#{index + 1}" width="#{width}" customWidth="1"/>) }.join}
          </cols>
          <sheetData>
            #{rows.each_with_index.map { |row, index| dashboard_report_xlsx_row_xml(index + 1, row) }.join}
          </sheetData>
          <autoFilter ref="A4:#{last_column}#{rows.size}"/>
          <pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>
        </worksheet>
      XML
    end

    def dashboard_report_xlsx_row_xml(row_index, row)
      style_id = dashboard_report_xlsx_style_id(row[:style])
      cells = row.fetch(:cells).each_with_index.map do |value, column_index|
        cell_style = value.is_a?(Hash) ? dashboard_report_xlsx_style_id(value[:style]) : style_id
        cell_value = value.is_a?(Hash) ? value[:value] : value
        dashboard_report_xlsx_cell_xml(row_index, column_index + 1, cell_value, cell_style)
      end.join

      %(<row r="#{row_index}">#{cells}</row>)
    end

    def dashboard_report_xlsx_cell_xml(row_index, column_index, value, style_id)
      reference = "#{xlsx_column_name(column_index)}#{row_index}"
      return %(<c r="#{reference}" s="#{style_id}"/>) if value.blank?

      %(<c r="#{reference}" s="#{style_id}" t="inlineStr"><is><t>#{CGI.escapeHTML(value.to_s)}</t></is></c>)
    end

    def dashboard_report_xlsx_style_id(style)
      {
        blank: 0,
        title: 1,
        period: 2,
        group_header: 3,
        group_summary: 4,
        lead_header: 5,
        lead_body: 6,
        lead: 7,
        rotary: 8,
        pool: 9,
        positive: 10,
        contact: 11,
        opportunity: 12,
        warning: 13,
        danger: 14,
        muted: 15
      }.fetch(style || :blank)
    end

    def dashboard_report_xlsx_content_types_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
      XML
    end

    def dashboard_report_xlsx_root_relationships_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
      XML
    end

    def dashboard_report_xlsx_workbook_xml(sheet_name)
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets><sheet name="#{CGI.escapeHTML(sheet_name)}" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
      XML
    end

    def dashboard_report_xlsx_workbook_relationships_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
      XML
    end

    def dashboard_report_xlsx_app_properties_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
          <Application>Unitymob</Application>
        </Properties>
      XML
    end

    def dashboard_report_xlsx_core_properties_xml
      generated_at = CGI.escapeHTML(Time.current.utc.iso8601)
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:creator>Unitymob</dc:creator>
          <cp:lastModifiedBy>Unitymob</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">#{generated_at}</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">#{generated_at}</dcterms:modified>
        </cp:coreProperties>
      XML
    end

    def dashboard_report_xlsx_styles_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="4">
            <font><sz val="11"/><name val="Arial"/><color rgb="FF1F2937"/></font>
            <font><b/><sz val="14"/><name val="Arial"/><color rgb="FFFFFFFF"/></font>
            <font><b/><sz val="11"/><name val="Arial"/><color rgb="FF1F2937"/></font>
            <font><b/><sz val="11"/><name val="Arial"/><color rgb="FFFFFFFF"/></font>
          </fonts>
          <fills count="12">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FF1F2937"/><bgColor indexed="64"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFEAF2FF"/><bgColor indexed="64"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFDDEBFA"/><bgColor indexed="64"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFF3F7FC"/><bgColor indexed="64"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFF8FAFD"/><bgColor indexed="64"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFEAF3FF"/><bgColor indexed="64"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFF3E8FF"/><bgColor indexed="64"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFEAFBF1"/><bgColor indexed="64"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFFFF4DE"/><bgColor indexed="64"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFFFE8E8"/><bgColor indexed="64"/></patternFill></fill>
          </fills>
          <borders count="3">
            <border><left/><right/><top/><bottom/><diagonal/></border>
            <border><left style="thin"><color rgb="FFD6DEE8"/></left><right style="thin"><color rgb="FFD6DEE8"/></right><top style="thin"><color rgb="FFD6DEE8"/></top><bottom style="thin"><color rgb="FFD6DEE8"/></bottom><diagonal/></border>
            <border><left style="thin"><color rgb="FFFFFFFF"/></left><right style="thin"><color rgb="FFFFFFFF"/></right><top style="thin"><color rgb="FFFFFFFF"/></top><bottom style="thin"><color rgb="FFFFFFFF"/></bottom><diagonal/></border>
          </borders>
          <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
          <cellXfs count="16">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="5" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="0" fillId="6" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
            <xf numFmtId="0" fontId="2" fillId="7" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="7" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="8" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="9" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="10" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="10" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="11" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
            <xf numFmtId="0" fontId="2" fillId="5" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          </cellXfs>
          <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
          <dxfs count="0"/>
          <tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/>
        </styleSheet>
      XML
    end

    def xlsx_column_name(index)
      name = +""
      while index.positive?
        index -= 1
        name.prepend((65 + (index % 26)).chr)
        index /= 26
      end
      name
    end

    def build_xlsx_package(entries)
      offset = 0
      central_directory = +"".b
      file_data = +"".b
      mod_time, mod_date = xlsx_zip_timestamp

      entries.each do |path, content|
        name = path.b
        body = content.to_s.b
        crc = Zlib.crc32(body)
        local_header = [0x04034b50, 20, 0, 0, mod_time, mod_date, crc, body.bytesize, body.bytesize, name.bytesize, 0].pack("VvvvvvVVVvv")
        central_header = [0x02014b50, 20, 20, 0, 0, mod_time, mod_date, crc, body.bytesize, body.bytesize, name.bytesize, 0, 0, 0, 0, 0, offset].pack("VvvvvvvVVVvvvvvVV")

        file_data << local_header << name << body
        central_directory << central_header << name
        offset = file_data.bytesize
      end

      end_record = [0x06054b50, 0, 0, entries.size, entries.size, central_directory.bytesize, file_data.bytesize, 0].pack("VvvvvVVv")
      file_data << central_directory << end_record
    end

    def xlsx_zip_timestamp
      now = Time.current
      [
        (now.hour << 11) | (now.min << 5) | (now.sec / 2),
        ((now.year - 1980) << 9) | (now.month << 5) | now.day
      ]
    end

  end
end
