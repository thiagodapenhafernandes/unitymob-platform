require "spec_helper"

RSpec.describe "AI property search transcriber contract" do
  let(:source) { File.read(File.expand_path("../../app/services/ai/property_search/transcriber.rb", __dir__)) }

  it "discards vocabulary prompt echoes before they reach the search textarea" do
    expect(source).to include("sanitize_transcription(transcription, prompt:)")
    expect(source).to include("text.include?(prompt_text)")
    expect(source).to include('text.match?(/\A(?:contexto?|context):\s*#+\s*Vocabulário:/i)')
    expect(source).to include('return "" if text.start_with?("Vocabulário:")')
  end
end
