require "zlib"

module Downloads
  class ZipArchive
    Entry = Struct.new(:name, :data, keyword_init: true)

    class << self
      def build(entries)
        new(entries).build
      end
    end

    def initialize(entries)
      @entries = Array(entries).filter_map do |entry|
        name = sanitize_name(entry[:name] || entry["name"])
        data = entry[:data] || entry["data"]
        next if name.blank? || data.blank?

        Entry.new(name: name, data: data.b)
      end
    end

    def build
      output = String.new.b
      central_directory = String.new.b

      @entries.each do |entry|
        offset = output.bytesize
        local_header = local_file_header(entry)
        output << local_header << entry.data
        central_directory << central_directory_header(entry, offset)
      end

      output << central_directory
      output << end_of_central_directory(@entries.size, central_directory.bytesize, output.bytesize - central_directory.bytesize)
      output
    end

    private

    def sanitize_name(name)
      basename = File.basename(name.to_s)
      basename = "arquivo" if basename.blank? || basename == "."
      basename.gsub(/[^\w.\-]+/, "_")
    end

    def local_file_header(entry)
      [
        0x04034b50,
        20,
        0,
        0,
        dos_time,
        dos_date,
        Zlib.crc32(entry.data),
        entry.data.bytesize,
        entry.data.bytesize,
        entry.name.bytesize,
        0
      ].pack("VvvvvvVVVvv") << entry.name
    end

    def central_directory_header(entry, local_header_offset)
      [
        0x02014b50,
        20,
        20,
        0,
        0,
        dos_time,
        dos_date,
        Zlib.crc32(entry.data),
        entry.data.bytesize,
        entry.data.bytesize,
        entry.name.bytesize,
        0,
        0,
        0,
        0,
        0,
        local_header_offset
      ].pack("VvvvvvvVVVvvvvvVV") << entry.name
    end

    def end_of_central_directory(entry_count, central_directory_size, central_directory_offset)
      [
        0x06054b50,
        0,
        0,
        entry_count,
        entry_count,
        central_directory_size,
        central_directory_offset,
        0
      ].pack("VvvvvVVv")
    end

    def dos_time
      time = Time.current
      (time.hour << 11) | (time.min << 5) | (time.sec / 2)
    end

    def dos_date
      time = Time.current
      ((time.year - 1980) << 9) | (time.month << 5) | time.day
    end
  end
end
