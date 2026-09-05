namespace :support, path: "admin/support" do
  get :updates, to: "tickets#updates"
  resources :tickets, only: [:index, :new, :create, :show, :update] do
    post :messages, on: :member
    post :notes, on: :member
    patch :revise_message, on: :member
    delete :remove_message, on: :member
    post :access, on: :member
    get :attachment, on: :member
  end
end
post "/internal/support/v1/events", to: "support/events#create"
post "/internal/support/v1/access", to: "support/access_grants#create"
post "/support/access", to: "support/access_grants#consume", as: nil
delete "/support/access", to: "support/access_grants#destroy", as: :support_access

post "/internal/support/v1/accounts", to: "support/registrations#create"

post "/internal/support/v1/recipients", to: "support/recipients#create"
