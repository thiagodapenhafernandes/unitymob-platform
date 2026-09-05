Rails.application.routes.draw do
  patch "/queue_preferences", to: "queue_preferences#update"
  resources :support_labels, only: [:index, :create, :update, :destroy] do
    post :apply, on: :member
  end
  resources :notifications, only: [:index, :create]
  get "/up", to: "rails/health#show"
  get "/finance", to: "management#finance", as: :finance
  post "/presence", to: "presence#create", as: :presence
  get "/sla", to: "sla#index", as: :sla
  patch "/sla/policies", to: "sla#update", as: :sla_policies
  get "/outreach/users", to: "outreach#users", as: :outreach_users
  post "/outreach", to: "outreach#create", as: :outreach
  root to: "management#dashboard"
  get "/login", to: "sessions#new"
  post "/login", to: "sessions#create"
  get "/login/verify", to: "sessions#verify", as: :verify_login
  post "/login/verify", to: "sessions#verify_email"
  get "/login/authenticator", to: "sessions#authenticator", as: :verify_authenticator
  post "/login/authenticator", to: "sessions#verify_authenticator"
  delete "/logout", to: "sessions#destroy"
  get "/activate", to: "sessions#edit", as: :activate
  patch "/activate", to: "sessions#update"
  get "/management", to: "management#index", as: :management
  post "/management/staff", to: "management#create_staff", as: :management_staff
  patch "/management/staff/:id", to: "management#update_staff", as: :management_staff_member
  patch "/management/accounts/:id", to: "management#update_account", as: :management_account
  instance_eval File.read(Rails.root.join("../support/routes.rb")), "support/routes.rb"
end
