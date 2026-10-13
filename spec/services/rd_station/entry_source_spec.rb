require "rails_helper"

RSpec.describe RdStation::EntrySource do
  def source(contact)
    described_class.call("contact" => contact)[:key]
  end

  it "identifica origem oficial do funil e valores UTM de qualquer fonte" do
    expect(source("funnel" => {"origin" => "Busca Paga | Google"})).to eq("google")
    expect(source("funnel" => {"origin" => "Social | Facebook"})).to eq("meta")
    expect(source("origin" => {"utm_source" => "linkedin"})).to eq("linkedin")
    expect(source("utm_source" => " Parceiro Áurea ")).to eq("parceiro aurea")
    expect(source("utm_source" => "tiktok_ads")).to eq("tiktok")
  end

  it "reconhece tags Meta quando o RD não informou a origem" do
    expect(source("funnel" => {"origin" => "Desconhecido"}, "tags" => ["instagram leads"])).to eq("meta")
    expect(source("tags" => ["facebook leads"])).to eq("meta")
  end

  it "prioriza fonte explícita e não usa perfil social ou nome de formulário" do
    expect(source("utm_source" => "newsletter", "tags" => ["instagram leads"])).to eq("newsletter")
    expect(source("facebook" => "perfil", "conversion_identifier" => "Facebook formulário")).to eq("unknown")
    expect(source("utm_medium" => "email")).to eq("email")
    expect(source("utm_source" => "newsletter", "utm_medium" => "email")).to eq("email")
    expect(source({})).to eq("unknown")
  end
end
