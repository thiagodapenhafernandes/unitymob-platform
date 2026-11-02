require "rails_helper"

RSpec.describe Habitation::PortalReel do
  let(:habitation) { build(:habitation) }

  def attach_reel(filename: "reel.mp4", content_type: "video/mp4", metadata: {})
    habitation.portal_reel.attach(io: StringIO.new("video"), filename: filename, content_type: content_type, identify: false)
    habitation.portal_reel.blob.metadata = metadata.stringify_keys
  end

  it "keeps properties without a reel valid and out of the reel feed" do
    expect(habitation).to be_valid
    expect(habitation.portal_reel_exportable?).to be(false)
  end

  it "waits for server analysis instead of trusting the extension" do
    attach_reel
    expect(habitation).to be_valid
    expect(habitation.portal_reel_exportable?).to be(false)
    expect(habitation.portal_reel_status).to include("Aguardando")
  end

  ["mp4", "mov"].each do |extension|
    [10, 60].each do |duration|
      it "exports a vertical #{extension} at the #{duration}s boundary" do
        attach_reel(filename: "reel.#{extension}", content_type: extension == "mov" ? "video/quicktime" : "video/mp4",
                    metadata: { analyzed: true, duration: duration, width: 1080, height: 1920 })
        expect(habitation).to be_valid
        expect(habitation.portal_reel_exportable?).to be(true)
      end
    end
  end

  [
    { duration: 9.9, width: 1080, height: 1920 },
    { duration: 60.1, width: 1080, height: 1920 },
    { duration: 30, width: 1920, height: 1080 },
    { duration: 30, width: 1080, height: 0 },
    {}
  ].each do |metadata|
    it "rejects unsupported analyzed metadata #{metadata}" do
      attach_reel(metadata: metadata.merge(analyzed: true))
      expect(habitation).not_to be_valid
      expect(habitation.portal_reel_exportable?).to be(false)
      expect(habitation.errors[:portal_reel]).to be_present
    end
  end

  it "rejects unsupported formats" do
    attach_reel(filename: "reel.webm", content_type: "video/webm")
    expect(habitation).not_to be_valid
    expect(habitation.portal_reel_exportable?).to be(false)
  end

  it "rejects files larger than 80 MB but accepts the boundary" do
    attach_reel
    habitation.portal_reel.blob.byte_size = 80_000_000
    expect(habitation).to be_valid
    habitation.portal_reel.blob.byte_size += 1
    expect(habitation).not_to be_valid
    expect(habitation.portal_reel_exportable?).to be(false)
  end

  it "does not block unrelated edits after an invalid video is analyzed" do
    habitation = create(:habitation)
    habitation.portal_reel.attach(io: StringIO.new("video"), filename: "reel.mp4", content_type: "video/mp4", identify: false)
    habitation.portal_reel.blob.update!(metadata: { analyzed: true })
    habitation.reload
    expect(habitation.update(titulo_anuncio: "Título atualizado")).to be(true)
    expect(habitation.portal_reel_exportable?).to be(false)
  end
  it "uses the native analyzer on a real 10-second vertical MP4" do
    record = create(:habitation)
    File.open(Rails.root.join("spec/fixtures/files/portal_reel.mp4")) do |file|
      record.portal_reel.attach(io: file, filename: "reel.mp4", content_type: "video/mp4")
    end
    record.portal_reel.blob.analyze
    expect(record.reload.portal_reel_exportable?).to be(true)
    expect(record.portal_reel.blob.metadata).to include("width" => 90, "height" => 160, "duration" => 10)
  end

end
