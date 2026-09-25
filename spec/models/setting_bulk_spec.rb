require "rails_helper"

RSpec.describe Setting, ".get com bulk-load" do
  let(:tenant) { Tenant.create!(name: "Bulk #{SecureRandom.hex(3)}", slug: "bulk-#{SecureRandom.hex(3)}") }

  def setting_queries(&block)
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 if payload[:sql].to_s.include?('"settings"')
    end
    block.call
    ActiveSupport::Notifications.unsubscribe(subscriber)
    count
  end

  it "escopo vence, global como fallback e default sem fallback" do
    Setting.set("cor_site", "azul", nil, tenant: tenant)
    Setting.set("cor_site", "verde", nil, tenant: nil)
    Setting.set("sombra", "global", nil, tenant: nil)

    expect(Setting.get("cor_site", nil, tenant: tenant)).to eq("azul")
    expect(Setting.get("sombra", nil, tenant: tenant)).to eq("global")
    expect(Setting.get("ausente", "padrao", tenant: tenant)).to eq("padrao")
    expect(Setting.get("sombra", "padrao", tenant: tenant, fallback_global: false)).to eq("padrao")
  end

  it "lê N chaves com 1 query" do
    5.times { |i| Setting.set("chave_#{i}", "valor_#{i}", nil, tenant: tenant) }

    queries = setting_queries do
      5.times { |i| Setting.get("chave_#{i}", nil, tenant: tenant) }
    end
    expect(queries).to eq(1)
  end

  it "escrita invalida a leitura seguinte no mesmo request" do
    Setting.set("tema", "claro", nil, tenant: tenant)
    expect(Setting.get("tema", nil, tenant: tenant)).to eq("claro")

    Setting.set("tema", "escuro", nil, tenant: tenant)
    expect(Setting.get("tema", nil, tenant: tenant)).to eq("escuro")
  end
end
