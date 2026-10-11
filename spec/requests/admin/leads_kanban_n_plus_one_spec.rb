require "rails_helper"

RSpec.describe "Admin leads kanban includes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "kanban-n1-#{SecureRandom.hex(8)}@salute.test") }
  let(:tenant) { admin.tenant }
  let!(:pipeline) { create(:lead_pipeline, tenant: tenant) }
  let!(:stages) do
    %w[Triagem Contato].map do |name|
      stage = create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline, name: name)
      create(:lead_pipeline_stage_policy, lead_pipeline_stage: stage, tenant: tenant)
      stage
    end
  end

  before do
    host! "localhost"
    sign_in admin
    create(:lead, tenant: tenant, name: "CardLead Alpha", lead_pipeline: pipeline,
      lead_pipeline_stage: stages.first, status: "Triagem")
    2.times do |i|
      create(:lead, tenant: tenant, name: "CardLead Extra #{i}", lead_pipeline: pipeline,
        lead_pipeline_stage: stages.last, status: "Contato")
    end
  end

  def collect_stage_sql
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      queries << sql.squish if sql.include?("lead_pipeline_stage")
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  it "preloads card stages and policies instead of querying per card" do
    queries = collect_stage_sql { get admin_lead_pipeline_leads_path(pipeline, view: "kanban") }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css("article.lead-kanban-card").size).to eq(3)

    by_id_stage = queries.select { |sql| sql.match?(/FROM "lead_pipeline_stages" WHERE "lead_pipeline_stages"\."id" =/) }
    expect(by_id_stage).to be_empty

    single_policy = queries.select do |sql|
      sql.include?('FROM "lead_pipeline_stage_policies"') && !sql.include?(" IN (")
    end
    expect(single_policy).to be_empty
  end
end
