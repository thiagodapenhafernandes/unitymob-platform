require "rails_helper"

RSpec.describe "Reparo de contatos do catálogo" do
  it "simula sem gravar e preenche apenas contatos vazios do proprietário identificado na origem" do
    tenant = Tenant.default
    owner = tenant.proprietors.create!(name: "Repair owner", vista_code: "REPAIR-OWNER", email: "manual@example.test")
    habitation = create(:habitation, tenant: tenant, proprietor: owner, proprietario_celular: nil)
    allow_any_instance_of(SyncPropertyService).to receive(:fetch_details).and_return(
      "Categoria" => "Apartamento", "proprietarios" => { "REPAIR-OWNER" => { "Codigo" => "REPAIR-OWNER", "FonePrincipal" => "(55) 99999-1234", "EmailResidencial" => "source@example.test" } }
    )
    keys = %w[TENANT_ID CODES OPERATIONS EXECUTE]
    previous = ENV.to_h.slice(*keys)
    ENV.update("TENANT_ID" => tenant.id.to_s, "CODES" => habitation.codigo, "OPERATIONS" => "owner_contacts", "EXECUTE" => "0")
    path = Rails.root.join("script/maintenance/repair_property_catalog.rb")

    expect { load path }.to output(/phone_primary/).to_stdout
    expect(owner.reload.phone_primary).to be_blank
    expect(habitation.reload.proprietario_celular).to be_blank

    ENV["EXECUTE"] = "1"
    expect { load path }.to output(/phone_primary/).to_stdout
    expect(owner.reload.phone_primary).to be_present
    expect(owner.email).to eq("manual@example.test")
    expect(habitation.reload.proprietario_celular).to be_present
  ensure
    keys&.each { |key| previous&.key?(key) ? ENV[key] = previous[key] : ENV.delete(key) }
  end
end
