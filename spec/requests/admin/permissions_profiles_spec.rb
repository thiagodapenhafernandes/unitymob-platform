require "rails_helper"

RSpec.describe "Admin profile permissions", type: :request do
  include Devise::Test::IntegrationHelpers

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = Tenant.default
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  before { host! "localhost" }

  def agent_profile
    Tenant.default.profiles.find_by!(key: "agent").tap do |profile|
      profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    end
  end

  def build_manager_profile(name: "Gerente #{SecureRandom.hex(6)}", position: 700)
    Profile.create!(
      tenant: Tenant.default,
      name: name,
      axis: Profile::AXES[:vertical],
      position: position,
      permissions: Profile.default_permissions_for("Gerente")
    )
  end

  it "bloqueia gerente de imprimir e exportar imóveis" do
    manager_profile = build_manager_profile(position: 700)
    manager = create(:admin_user, profile: manager_profile)

    sign_in manager

    post export_admin_habitations_path
    expect(response).to redirect_to(admin_habitations_path)

    get exports_admin_habitations_path
    expect(response).to redirect_to(admin_habitations_path)

    get print_admin_habitations_path
    expect(response).to redirect_to(admin_habitations_path)
  end

  it "permite gerente editar pendência de revisão apenas do próprio time" do
    manager_profile = build_manager_profile(name: "Gerente revisão #{SecureRandom.hex(6)}", position: 750)
    manager = create(:admin_user, profile: manager_profile, acting_type: :sales)
    team_broker = create(:admin_user, manager: manager, acting_type: :sales)
    outside_broker = create(:admin_user, acting_type: :sales)
    team_intake = create(:habitation, :broker_intake, codigo: "CAP-EDIT-TEAM-#{SecureRandom.hex(5)}", admin_user: team_broker, intake_status: "submitted_for_admin_review")
    outside_intake = create(:habitation, :broker_intake, codigo: "CAP-EDIT-OUT-#{SecureRandom.hex(5)}", admin_user: outside_broker, intake_status: "submitted_for_admin_review")

    sign_in manager

    get edit_admin_habitation_path(team_intake)
    expect(response).to have_http_status(:ok)

    get edit_admin_habitation_path(outside_intake)
    expect(response).to redirect_to(admin_habitations_path)
  end

  it "aplica manage, review e scope team a qualquer perfil vertical com hierarquia" do
    manager_profile = Profile.create!(
      tenant: Tenant.default,
      name: "Coordenação vertical #{SecureRandom.hex(6)}",
      axis: Profile::AXES[:vertical],
      position: 760,
      permissions: {
        "imoveis" => { "view" => true, "media" => true, "manage" => true, "scope" => "team" },
        "captacoes" => { "view" => true, "manage" => true, "review" => true, "scope" => "team" }
      }
    )
    manager = create(:admin_user, profile: manager_profile, acting_type: :sales)
    team_broker = create(:admin_user, manager: manager, acting_type: :sales)
    outside_broker = create(:admin_user, acting_type: :sales)
    team_intake = create(
      :habitation,
      :broker_intake,
      codigo: "CAP-TEAM-#{SecureRandom.hex(5)}",
      titulo_anuncio: "Captação da equipe #{SecureRandom.hex(4)}",
      admin_user: team_broker,
      intake_status: "submitted_for_admin_review",
      proprietario: "Proprietário da equipe"
    )
    outside_intake = create(
      :habitation,
      :broker_intake,
      codigo: "CAP-OUT-#{SecureRandom.hex(5)}",
      titulo_anuncio: "Captação externa #{SecureRandom.hex(4)}",
      admin_user: outside_broker,
      intake_status: "submitted_for_admin_review",
      proprietario: "Proprietário externo"
    )

    sign_in manager

    get admin_captacoes_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(team_intake.intake_display_title)
    expect(response.body).not_to include(outside_intake.intake_display_title)

    get admin_habitations_path(team: "0")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pendente de revisão")
    expect(response.body).not_to include("+ equipe")

    get admin_habitations_path(intake_review: "pending", ownership: "all", team: "0")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(team_intake.titulo_anuncio)
    expect(response.body).not_to include(outside_intake.titulo_anuncio)

    get admin_captacao_path(team_intake)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Revisão administrativa")

    get admin_captacao_path(outside_intake)
    expect(response).to redirect_to(admin_captacoes_path)

    post return_to_broker_admin_captacao_path(team_intake), params: {
      admin_review_return_reason: "Ajustar documentação",
      admin_review_notes: "Revisão do gerente"
    }
    expect(response).to redirect_to(admin_captacao_path(team_intake))
    expect(team_intake.reload.intake_status).to eq("returned_to_broker")

    post return_to_broker_admin_captacao_path(outside_intake), params: {
      admin_review_return_reason: "Tentativa fora da equipe",
      admin_review_notes: "Não deve revisar"
    }
    expect(response).to redirect_to(admin_captacoes_path)
    expect(outside_intake.reload.intake_status).to eq("submitted_for_admin_review")

    get modal_admin_habitation_media_path(team_intake), headers: { "X-Requested-With" => "XMLHttpRequest" }
    expect(response).to have_http_status(:ok)

    get modal_admin_habitation_media_path(outside_intake), headers: { "X-Requested-With" => "XMLHttpRequest" }
    expect(response).to redirect_to(admin_habitations_path)

    get edit_admin_habitation_path(team_intake)
    delete admin_habitation_path(team_intake)
    expect(response).to redirect_to(admin_habitations_path)
    expect(team_intake.reload).to be_persisted

    manager_profile.update!(permissions: manager_profile.permissions.deep_merge(
      "imoveis" => { "manage" => false },
      "captacoes" => { "review" => false }
    ))

    get edit_admin_habitation_path(team_intake)
    expect(response).to redirect_to(admin_habitations_path)

    team_intake.update!(intake_status: "submitted_for_admin_review")
    get admin_habitations_path(intake_review: "pending")
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(team_intake.titulo_anuncio)

    post return_to_broker_admin_captacao_path(team_intake), params: {
      admin_review_return_reason: "Tentativa sem permissão",
      admin_review_notes: "Não deve revisar"
    }
    expect(response).to redirect_to(admin_captacoes_path)
    expect(team_intake.reload.intake_status).to eq("submitted_for_admin_review")
  end

  it "bloqueia corretor de editar captação pendente de revisão" do
    broker_profile = agent_profile
    broker = create(:admin_user, profile: broker_profile)
    intake = create(:habitation, :broker_intake, admin_user: broker, intake_status: "submitted_for_admin_review")

    sign_in broker

    get edit_admin_captacao_path(intake)
    expect(response).to redirect_to(admin_captacoes_path)

    get edit_admin_habitation_path(intake)
    expect(response).to redirect_to(admin_habitations_path)
  end

  it "controla se o corretor aparece no site pelo cadastro administrativo" do
    admin = create(:admin_user, :admin)
    broker_profile = agent_profile
    broker = create(:admin_user, profile: broker_profile, display_on_site: true)

    sign_in admin

    get edit_admin_admin_user_path(broker)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Exibir perfil no site")

    patch admin_admin_user_path(broker), params: {
      admin_user: {
        name: broker.name,
        email: broker.email,
        profile_id: broker.profile_id,
        acting_type: broker.acting_type,
        active: "1",
        display_on_site: "0"
      }
    }

    expect(response).to redirect_to(admin_admin_users_path)
    expect(broker.reload.display_on_site).to be(false)
  end

  it "ignora role legado enviado no payload de usuário" do
    tenant = Tenant.create!(name: "Tenant role #{SecureRandom.hex(3)}", slug: "tenant-role-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor)
    user = create(:admin_user, tenant: tenant, profile: agent_profile, role: :editor)

    sign_in owner

    patch admin_admin_user_path(user), params: {
      admin_user: {
        name: user.name,
        email: user.email,
        profile_id: agent_profile.id,
        role: "admin"
      }
    }

    expect(response).to redirect_to(admin_admin_users_path)
    expect(user.reload.role).to eq("editor")
    expect(user.admin?).to be(false)
  end

  it "não concede integrações nem dashboard de captação ao perfil padrão de corretor" do
    permissions = Profile.default_permissions_for("Corretor")

    expect(permissions.dig("captacoes", "view")).to be(true)
    expect(permissions.dig("imoveis", "media")).to be(true)
    expect(permissions["captacao_dashboard"]).to be_nil
    expect(permissions["integracoes"]).to be_nil
  end

  it "bloqueia webhooks para corretor mesmo por URL direta" do
    broker_profile = agent_profile
    broker = create(:admin_user, profile: broker_profile)

    sign_in broker

    get admin_webhook_settings_path

    expect(response).to redirect_to(admin_root_path)
  end

  it "preserva escopo de equipe ao salvar perfil pela matriz de permissões" do
    admin = create(:admin_user, :admin)
    profile = build_manager_profile(name: "Gerente custom #{SecureRandom.hex(6)}", position: 800)

    sign_in admin

    patch admin_profile_path(profile), params: {
      profile: {
        name: profile.name,
        active: "1",
        axis: "vertical",
        position: "300",
        permissions: {
          admin: "0",
          leads: {
            view: "1",
            manage: "1",
            scope: "team"
          }
        }
      }
    }

    expect(response).to redirect_to(edit_admin_profile_path(profile))
    expect(profile.reload.permissions.dig("leads", "scope")).to eq("team")
  end

  it "só sai da edição do perfil quando o usuário escolhe salvar e sair" do
    admin = create(:admin_user, :admin)
    profile = build_manager_profile(name: "Gerente navegação #{SecureRandom.hex(6)}", position: 820)

    sign_in admin
    get edit_admin_profile_path(profile)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('button[name="save_navigation"][value="stay"]')&.text&.squish).to eq("Salvar alterações")
    expect(document.at_css('button[name="save_navigation"][value="exit"]')&.text&.squish).to eq("Salvar e sair")

    patch admin_profile_path(profile), params: {
      save_navigation: "exit",
      profile: {
        name: profile.name,
        active: "1",
        axis: "vertical",
        position: profile.position.to_s,
        permissions: { admin: "0" }
      }
    }

    expect(response).to redirect_to(admin_profiles_path)
  end

  it "restringe a gestao de perfis ao Tenant Owner, ignorando permissao horizontal ampla" do
    tenant = Tenant.create!(name: "Tenant perfis #{SecureRandom.hex(3)}", slug: "tenant-perfis-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    manager_profile = Profile.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 300, permissions: { "corretores" => { "manage" => true } })
    horizontal = Profile.create!(
      tenant: tenant,
      name: "Backoffice amplo",
      axis: "horizontal",
      vertical_profile: manager_profile,
      permissions: {
        "corretores" => { "manage" => true },
        "automacoes" => { "manage" => true },
        "integracoes" => { "manage" => true }
      }
    )
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor)
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, horizontal_profile: horizontal, manager: owner)

    sign_in manager

    get admin_profiles_path
    expect(response).to redirect_to(admin_root_path)

    sign_in owner

    get admin_profiles_path
    expect(response).to have_http_status(:ok)
  end

  it "posiciona novo perfil vertical após o perfil escolhido sem permitir inserir após Agent" do
    admin = create(:admin_user, :admin)
    tenant = admin.tenant
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")

    sign_in admin

    get new_admin_profile_path

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    insert_after_select = doc.at_css("#profile_insert_after_profile_id")
    expect(insert_after_select).to be_present
    expect(insert_after_select.css("option").map { |option| option["value"] }).to include(owner_profile.id.to_s)
    expect(insert_after_select.css("option").map { |option| option["value"] }).not_to include(agent_profile.id.to_s)

    post admin_profiles_path, params: {
      profile: {
        name: "Superintendente #{SecureRandom.hex(4)}",
        axis: "vertical",
        insert_after_profile_id: owner_profile.id,
        active: "1",
        permissions: {
          admin: "0",
          leads: { view: "1", scope: "team" }
        }
      }
    }

    created_profile = tenant.profiles.where("name LIKE ?", "Superintendente%").first!
    expect(response).to redirect_to(edit_admin_profile_path(created_profile))
    expect(created_profile.position).to be > owner_profile.position
    expect(created_profile.position).to be < agent_profile.position
  end

  it "bloqueia payload forjado tentando inserir perfil vertical após Agent" do
    admin = create(:admin_user, :admin)
    agent_profile = admin.tenant.profiles.find_by!(key: "agent")

    sign_in admin

    expect {
      post admin_profiles_path, params: {
        profile: {
          name: "Perfil inválido #{SecureRandom.hex(4)}",
          axis: "vertical",
          insert_after_profile_id: agent_profile.id,
          active: "1",
          permissions: { admin: "0" }
        }
      }
    }.not_to change(Profile, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Selecione um perfil vertical acima do Agent.")
  end

  it "preserva a posição do perfil vertical existente quando a edição não muda a ordem" do
    admin = create(:admin_user, :admin)
    tenant = admin.tenant
    profile = Profile.create!(
      tenant: tenant,
      name: "Gerente posição #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 3_600,
      permissions: Profile.default_permissions_for("Gerente")
    )
    predecessor = tenant.profiles.vertical.where("position < ?", profile.position).order(position: :desc).first!

    sign_in admin

    patch admin_profile_path(profile), params: {
      profile: {
        name: profile.name,
        active: "1",
        axis: "vertical",
        insert_after_profile_id: predecessor.id,
        permissions: {
          admin: "0",
          leads: { view: "1", scope: "team" }
        }
      }
    }

    expect(response).to redirect_to(edit_admin_profile_path(profile))
    expect(profile.reload.position).to eq(3_600)
  end

  it "reequilibra posições quando não há espaço numérico ao inserir perfil vertical" do
    admin = create(:admin_user, :admin)
    tenant = admin.tenant
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    first = Profile.create!(tenant: tenant, name: "Diretoria #{SecureRandom.hex(4)}", axis: "vertical", position: 1, permissions: {})
    second = Profile.create!(tenant: tenant, name: "Gerência #{SecureRandom.hex(4)}", axis: "vertical", position: 2, permissions: {})

    sign_in admin

    post admin_profiles_path, params: {
      profile: {
        name: "Coordenação #{SecureRandom.hex(4)}",
        axis: "vertical",
        insert_after_profile_id: first.id,
        active: "1",
        permissions: { admin: "0" }
      }
    }

    created_profile = tenant.profiles.where("name LIKE ?", "Coordenação%").first!
    positions = tenant.profiles.vertical.order(:position).pluck(:position)

    expect(response).to redirect_to(edit_admin_profile_path(created_profile))
    expect(owner_profile.reload.position).to eq(0)
    expect(agent_profile.reload.position).to eq(10_000)
    expect(created_profile.position).to be > first.reload.position
    expect(created_profile.position).to be < second.reload.position
    expect(positions).to eq(positions.uniq)
    expect(positions).to all(be_between(0, 10_000).inclusive)
  end

  it "reequilibra posições quando perfil vertical existente é movido para um intervalo colado" do
    admin = create(:admin_user, :admin)
    tenant = admin.tenant
    first = Profile.create!(tenant: tenant, name: "Diretoria #{SecureRandom.hex(4)}", axis: "vertical", position: 1, permissions: {})
    second = Profile.create!(tenant: tenant, name: "Gerência #{SecureRandom.hex(4)}", axis: "vertical", position: 2, permissions: {})
    moving = Profile.create!(tenant: tenant, name: "Superintendência #{SecureRandom.hex(4)}", axis: "vertical", position: 5_000, permissions: {})

    sign_in admin

    patch admin_profile_path(moving), params: {
      profile: {
        name: moving.name,
        active: "1",
        axis: "vertical",
        insert_after_profile_id: first.id,
        permissions: { admin: "0" }
      }
    }

    positions = tenant.profiles.vertical.order(:position).pluck(:position)

    expect(response).to redirect_to(edit_admin_profile_path(moving))
    expect(moving.reload.position).to be > first.reload.position
    expect(moving.position).to be < second.reload.position
    expect(positions).to eq(positions.uniq)
  end

  it "permite converter perfil vertical não fixo em horizontal e reconcilia usuários vinculados" do
    admin = create(:admin_user, :admin)
    tenant = admin.tenant
    profile = Profile.create!(
      tenant: tenant,
      name: "Coordenador #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 4_200,
      permissions: {}
    )
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    user = create(:admin_user, tenant: tenant, profile: profile, manager: admin)

    sign_in admin

    patch admin_profile_path(profile), params: {
      profile: {
        name: profile.name,
        active: "1",
        axis: "horizontal",
        vertical_profile_id: owner_profile.id,
        permissions: { admin: "0" }
      }
    }

    expect(response).to redirect_to(edit_admin_profile_path(profile))
    expect(profile.reload).to be_horizontal
    expect(profile.vertical_profile).to eq(owner_profile)
    expect(user.reload.profile).to eq(owner_profile)
    expect(user.horizontal_profile).to eq(profile)
    expect(user.manager).to be_nil
  end

  it "permite trocar o nível vertical de uma função horizontal e reconcilia usuários vinculados" do
    admin = create(:admin_user, :admin)
    tenant = admin.tenant
    manager = Profile.create!(tenant: tenant, name: "Manager #{SecureRandom.hex(4)}", axis: "vertical", position: 4_300, permissions: {})
    director = Profile.create!(tenant: tenant, name: "Director #{SecureRandom.hex(4)}", axis: "vertical", position: 4_100, permissions: {})
    horizontal = Profile.create!(tenant: tenant, name: "Backoffice #{SecureRandom.hex(4)}", axis: "horizontal", vertical_profile: manager, permissions: {})
    user = create(:admin_user, tenant: tenant, profile: manager, horizontal_profile: horizontal, manager: admin)

    sign_in admin

    patch admin_profile_path(horizontal), params: {
      profile: {
        name: horizontal.name,
        active: "1",
        axis: "horizontal",
        vertical_profile_id: director.id,
        permissions: { admin: "0" }
      }
    }

    expect(response).to redirect_to(edit_admin_profile_path(horizontal))
    expect(horizontal.reload.vertical_profile).to eq(director)
    expect(user.reload.profile).to eq(director)
    expect(user.horizontal_profile).to eq(horizontal)
    expect(user.manager).to be_nil
  end

  it "explica que acesso total horizontal é funcional e não altera hierarquia" do
    admin = create(:admin_user, :admin)
    tenant = admin.tenant
    manager = Profile.create!(tenant: tenant, name: "Manager #{SecureRandom.hex(4)}", axis: "vertical", position: 4_300, permissions: {})
    horizontal = Profile.create!(tenant: tenant, name: "Auditoria #{SecureRandom.hex(4)}", axis: "horizontal", vertical_profile: manager, permissions: { "admin" => true })

    sign_in admin

    get edit_admin_profile_path(horizontal)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Acesso funcional total")
    expect(response.body).to include("não transforma o usuário em Tenant Owner")
    expect(response.body).to include("não remove o limite do perfil vertical")
  end

  it "mostra apenas campos estruturais compatíveis com o eixo horizontal" do
    admin = create(:admin_user, :admin)
    profile = admin.tenant.profiles.find_by!(key: "administrativo")

    sign_in admin

    get edit_admin_profile_path(profile)

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("#profile_axis")).to be_present
    expect(doc.at_css("#profile_axis")["disabled"]).to be_nil
    vertical_profile_field = doc.at_css('[data-profile-axis-context-target="verticalProfileField"]')
    insert_after_field = doc.at_css('[data-profile-axis-context-target="insertAfterField"]')

    expect(vertical_profile_field).to be_present
    expect(vertical_profile_field["hidden"]).to be_nil
    expect(insert_after_field).to be_present
    expect(insert_after_field.has_attribute?("hidden")).to be(true)
    expect(doc.at_css("#profile_vertical_profile_id")["disabled"]).to be_nil
  end

  it "mostra apenas campos estruturais compatíveis com o eixo vertical" do
    admin = create(:admin_user, :admin)
    profile = admin.tenant.profiles.vertical.find_by!(name: Profile::INTERNAL_MANAGEMENT_PROFILE_NAME)

    sign_in admin

    get edit_admin_profile_path(profile)

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    vertical_profile_field = doc.at_css('[data-profile-axis-context-target="verticalProfileField"]')
    insert_after_field = doc.at_css('[data-profile-axis-context-target="insertAfterField"]')

    expect(vertical_profile_field).to be_present
    expect(vertical_profile_field.has_attribute?("hidden")).to be(true)
    expect(insert_after_field).to be_present
    expect(insert_after_field["hidden"]).to be_nil
    expect(doc.at_css("#profile_insert_after_profile_id")["disabled"]).to be_nil
  end

  it "não informa sucesso ao tentar excluir perfil vertical com função horizontal vinculada" do
    admin = create(:admin_user, :admin)
    tenant = admin.tenant
    vertical = Profile.create!(tenant: tenant, name: "Coordenação #{SecureRandom.hex(4)}", axis: "vertical", position: 4_200, permissions: {})
    horizontal = Profile.create!(tenant: tenant, name: "Backoffice #{SecureRandom.hex(4)}", axis: "horizontal", vertical_profile: vertical, permissions: {})

    sign_in admin

    expect do
      delete admin_profile_path(vertical)
    end.not_to change(Profile, :count)

    expect(response).to redirect_to(admin_profiles_path)
    expect(flash[:alert]).to include("este perfil é base das funções horizontais")
    expect(flash[:alert]).to include(horizontal.name)
    expect(flash[:alert]).to include("altere o campo “Vinculado a”")
    expect(flash[:notice]).to be_blank
    expect(Profile.exists?(vertical.id)).to be(true)
  end

  it "exclui perfil sem usuários e sem funções vinculadas" do
    admin = create(:admin_user, :admin)
    profile = Profile.create!(tenant: admin.tenant, name: "Temporário #{SecureRandom.hex(4)}", axis: "vertical", position: 4_200, permissions: {})

    sign_in admin

    expect do
      delete admin_profile_path(profile)
    end.to change(Profile, :count).by(-1)

    expect(response).to redirect_to(admin_profiles_path)
    expect(flash[:notice]).to eq("Perfil excluído.")
    expect(Profile.exists?(profile.id)).to be(false)
  end
end
