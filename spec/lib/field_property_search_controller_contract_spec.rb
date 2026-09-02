require "spec_helper"

RSpec.describe "field property search controller contract" do
  let(:source) { File.read(File.expand_path("../../app/javascript/controllers/field_property_search_controller.js", __dir__)) }

  it "does not expose voice recording controls when the WebView cannot record audio" do
    expect(source).to include("this.configureAudioRecording()")
    expect(source).to include("navigator.mediaDevices?.getUserMedia")
    expect(source).to include('typeof MediaRecorder !== "undefined"')
    expect(source).to include("this.micButtonTarget.hidden = !this.audioRecordingSupported()")
    expect(source).to include("cleanTranscription")
    expect(source).to include("(contexto?|context)")
  end
end
