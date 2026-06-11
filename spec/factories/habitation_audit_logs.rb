FactoryBot.define do
  factory :habitation_audit_log do
    habitation
    admin_user
    action { "updated" }
    source { "admin" }
    changed_fields { ["titulo_anuncio"] }
    changeset do
      {
        "titulo_anuncio" => {
          "before" => "Título antigo",
          "after" => "Título novo"
        }
      }
    end
    metadata { {} }
    created_at { Time.current }
  end
end
