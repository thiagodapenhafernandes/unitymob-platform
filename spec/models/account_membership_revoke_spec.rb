require "rails_helper"

# Hardening multi-conta: a revogação de uma membership DEVE ser atômica com a
# desativação do espelho. Se a desativação falhar, a transação inteira aborta —
# nunca fica uma membership "revogada" com espelho ainda ativo (acesso
# cross-tenant residual).
RSpec.describe AccountMembership, "#revoke!", type: :model do
  def agent_profile_for(tenant)
    tenant.profiles.find_or_create_by!(key: "agent") do |profile|
      profile.name = "Agent"
      profile.axis = "vertical"
      profile.permissions = { "leads" => { "view" => true, "scope" => "own" } }
    end
  end

  def owner_profile_for(tenant)
    tenant.profiles.find_or_create_by!(key: "tenant_owner") do |profile|
      profile.name = "Tenant Owner"
      profile.axis = "vertical"
      profile.permissions = { "admin" => true }
    end
  end

  # Espelho = admin_user comum na CONTA CONVIDADA (member_tenant), linkado ao
  # primário que vive em OUTRA conta (home_tenant). A membership pertence à
  # conta convidada.
  def build_membership
    home_tenant   = Tenant.create!(name: "Home #{SecureRandom.hex(3)}", slug: "home-#{SecureRandom.hex(4)}")
    member_tenant = Tenant.create!(name: "Member #{SecureRandom.hex(3)}", slug: "member-#{SecureRandom.hex(4)}")

    primary = create(:admin_user, tenant: home_tenant, profile: agent_profile_for(home_tenant))
    inviter = create(:admin_user, :admin, tenant: member_tenant, profile: owner_profile_for(member_tenant))
    member_profile = agent_profile_for(member_tenant)
    mirror  = create(:admin_user, tenant: member_tenant, profile: member_profile,
                                  primary_admin_user: primary, active: true)

    membership = AccountMembership.create!(
      tenant: member_tenant,
      invited_email: "convidado-#{SecureRandom.hex(4)}@salute.test",
      profile: member_profile,
      invited_by: inviter,
      primary_admin_user: primary,
      member_admin_user: mirror,
      status: :active,
      accepted_at: Time.current
    )

    [membership, mirror, inviter]
  end

  it "revoga a membership e desativa o espelho no caminho feliz" do
    membership, mirror, inviter = build_membership

    membership.revoke!(by: inviter)

    expect(membership.reload.status).to eq("revoked")
    expect(membership.revoked_by_id).to eq(inviter.id)
    expect(mirror.reload.active).to be(false)
  end

  it "aborta a transação inteira quando a desativação do espelho falha (usa update!)" do
    membership, mirror, inviter = build_membership

    # Simula falha ao desativar o espelho: com update! (bang) a exceção precisa
    # propagar e reverter TAMBÉM a revogação da membership.
    allow(membership).to receive(:member_admin_user).and_return(mirror)
    allow(mirror).to receive(:update!).with(active: false)
                                      .and_raise(ActiveRecord::RecordInvalid.new(mirror))

    expect { membership.revoke!(by: inviter) }.to raise_error(ActiveRecord::RecordInvalid)

    # Rollback: membership continua ativa e espelho continua ativo — sem estado
    # inconsistente que manteria acesso cross-tenant.
    expect(membership.reload.status).to eq("active")
    expect(membership.reload.revoked_at).to be_nil
    expect(mirror.reload.active).to be(true)
  end
end
