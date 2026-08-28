require "rails_helper"

RSpec.describe "Empreendimentos", type: :request do
  before { host! "localhost" }

  it "rejects malformed public development pages before pagination" do
    get empreendimentos_path(page: "12))) AND UPDATEXML(2297,CONCAT(0x7e,1,0x7e),1)-- -")

    expect(response).to have_http_status(:not_found)
  end
end
