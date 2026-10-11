require "rails_helper"

RSpec.describe System::RequestQueueTime do
  def request_with_header(value)
    env = Rack::MockRequest.env_for("/")
    env["HTTP_X_REQUEST_START"] = value if value
    ActionDispatch::Request.new(env)
  end

  it "parses nginx $msec timestamps" do
    request = request_with_header("1728500000.123")

    expect(described_class.ms(request, now: Time.zone.at(1728500001.123))).to eq(1000.0)
  end

  it "parses epoch millis (Heroku/router style)" do
    request = request_with_header("1728500000123")

    expect(described_class.ms(request, now: Time.zone.at(1728500001.123))).to eq(1000.0)
  end

  it "parses epoch seconds" do
    request = request_with_header("1728500000")

    expect(described_class.ms(request, now: Time.zone.at(1728500001))).to eq(1000.0)
  end

  it "accepts the t= prefix" do
    request = request_with_header("t=1728500000.123")

    expect(described_class.ms(request, now: Time.zone.at(1728500001.123))).to eq(1000.0)
  end

  it "returns nil without the header, with garbage, or on clock skew" do
    now = Time.zone.at(1728500001)

    expect(described_class.ms(request_with_header(nil), now: now)).to be_nil
    expect(described_class.ms(request_with_header(""), now: now)).to be_nil
    expect(described_class.ms(request_with_header("not-a-time"), now: now)).to be_nil
    expect(described_class.ms(request_with_header("9999999999"), now: now)).to be_nil
  end
end
