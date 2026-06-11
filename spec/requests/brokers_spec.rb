require "rails_helper"

RSpec.describe "Brokers", type: :request do
  before { host! "localhost" }

  it "exibe apenas corretores marcados para aparecer no site" do
    broker_profile = Profile.find_or_initialize_by(name: "Corretor")
    broker_profile.permissions = Profile.default_permissions_for("Corretor")
    broker_profile.active = true
    broker_profile.save!
    visible = create(:admin_user, name: "Corretor Visível", profile: broker_profile, active: true, display_on_site: true)
    hidden = create(:admin_user, name: "Corretor Oculto", profile: broker_profile, active: true, display_on_site: false)

    get brokers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(visible.name)
    expect(response.body).not_to include(hidden.name)
  end
end
