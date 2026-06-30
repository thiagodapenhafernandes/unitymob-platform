require "rails_helper"

RSpec.describe Admin::ContextItems, type: :controller do
  controller(ActionController::Base) do
    include Admin::ContextItems

    def index
      render plain: admin_context_items.size.to_s
    end

    def current_admin_user
      OpenStruct.new(id: 123, system_admin?: true)
    end

    def current_tenant
      nil
    end
  end

  before do
    routes.draw { get "index" => "anonymous#index" }
  end

  it "ignora atalhos operacionais quando Admin do Sistema está sem Tenant selecionado" do
    session[:admin_context_items] = [
      {
        "key" => "habitation:1",
        "type" => "habitation",
        "id" => 1,
        "admin_user_id" => 123
      }
    ]

    get :index

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("0")
  end
end
