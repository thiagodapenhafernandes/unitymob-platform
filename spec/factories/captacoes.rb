FactoryBot.define do
  factory :captacao do
    association :corretor, factory: :admin_user
    step { "intro" }
    completed { false }
    property_kind { :residencial }
    modalidade { :venda }

    trait :finished do
      completed { true }
      submitted_at { 1.day.ago }
      step { "review" }
      proprietario_nome { Faker::Name.name }
      proprietario_telefone { Faker::PhoneNumber.cell_phone }
      zip_code { "88330030" }
      street { "Avenida Atlântica" }
      street_number { "3750" }
      city { "Balneário Camboriú" }
      state { "SC" }
      area_privativa { 100 }
      area_total { 120 }
      dormitorios { 3 }
      banheiros { 2 }
      valor_venda { 1_200_000 }
    end

    trait :locacao do
      modalidade { :locacao_anual }
    end
  end

  factory :captacao_goal do
    start_date { Date.current.beginning_of_month }
    end_date { Date.current.end_of_month }
    kind { :venda }
    target { 55 }
    foco_regiao { "Frente Mar" }
  end
end
