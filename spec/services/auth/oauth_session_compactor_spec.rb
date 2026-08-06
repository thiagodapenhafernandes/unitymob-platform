require "rails_helper"

RSpec.describe Auth::OauthSessionCompactor do
  it "remove dados operacionais descartáveis antes do request phase do Facebook" do
    session = {
      "warden.user.admin_user.key" => [[123], "token"],
      "admin_context_items" => [{ "key" => "habitation:1", "label" => "Imóvel 1" }],
      "admin_context_skip_once_item_keys" => ["123:habitation:1"],
      "admin_habitations_last_filter:tenant:1:user:123" => { "q" => "x" * 500 },
      "omniauth.params" => { "utm_source" => "campanha" },
      "omniauth.state" => "state-token"
    }

    described_class.before_request_phase("rack.session" => session, "PATH_INFO" => "/auth/facebook")

    expect(session).to include("warden.user.admin_user.key")
    expect(session).to include("omniauth.state" => "state-token")
    expect(session).not_to include("admin_context_items")
    expect(session).not_to include("admin_context_skip_once_item_keys")
    expect(session).not_to include("admin_habitations_last_filter:tenant:1:user:123")
    expect(session).not_to include("omniauth.params")
  end

  it "remove origin e params depois do request phase sem apagar o state OAuth" do
    session = {
      "omniauth.origin" => "https://dev.unitymob.com.br/admin/habitations?#{'q=' + ('x' * 1000)}",
      "omniauth.params" => { "origin" => "https://dev.unitymob.com.br/admin/habitations" },
      "omniauth.state" => "state-token"
    }

    described_class.after_request_phase("rack.session" => session, "PATH_INFO" => "/auth/facebook")

    expect(session).to eq("omniauth.state" => "state-token")
  end

  it "não altera sessão de outros fluxos" do
    session = {
      "admin_context_items" => [{ "key" => "habitation:1" }],
      "omniauth.params" => { "foo" => "bar" }
    }

    described_class.before_request_phase("rack.session" => session, "PATH_INFO" => "/admin")

    expect(session).to include("admin_context_items", "omniauth.params")
  end
end
