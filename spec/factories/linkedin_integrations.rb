FactoryBot.define do
  factory :linkedin_integration do
    association :admin_user, :admin
    tenant { admin_user.tenant }
    access_token { "linkedin-test-token" }
    token_expires_at { 1.day.from_now }
    ad_accounts { [{ "id" => "123", "name" => "Conta LinkedIn" }] }
    selected_account_ids { ["123"] }
    account_cursors { { "123" => { "since" => (1.hour.ago.to_f * 1000).to_i } } }
    catalog_synced_at { Time.current }
    catalog do
      { "456" => { "name" => "Campanha LinkedIn", "account_id" => "123", "account_name" => "Conta LinkedIn", "forms" => [{ "id" => "789", "name" => "Formulário LinkedIn" }] } }
    end
  end
end
