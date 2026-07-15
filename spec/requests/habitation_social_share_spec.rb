require "rails_helper"

RSpec.describe "Compartilhamento social do imóvel (OG)", type: :request do
  before { host! "localhost" }

  it "usa a foto externa (import Vista/DWV) como og:image e inclui o código no título" do
    habitation = create(:habitation, codigo: "8903", slug: "apartamento-share-8903",
                        pictures: [{ "url" => "#{Storage::PublicPropertyPhoto.public_base_url}/spec/foto-8903.jpg", "ordem" => 1, "principal" => true }])

    get habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    og_image = response.body[/<meta property="og:image" content="([^"]*)"/, 1]
    expect(og_image).to include("foto-8903.jpg")
    expect(og_image).not_to include("icon.png")

    og_title = response.body[/<meta property="og:title" content="([^"]*)"/, 1]
    expect(og_title).to include("8903")
  end
end
