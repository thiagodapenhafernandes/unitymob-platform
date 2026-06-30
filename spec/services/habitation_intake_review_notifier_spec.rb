require "rails_helper"

RSpec.describe HabitationIntakeReviewNotifier do
  it "notifica revisores internos apenas do tenant da captação" do
    tenant = Tenant.create!(name: "Tenant #{SecureRandom.hex(3)}", slug: "tenant-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    reviewer_profile = Profile.create!(
      tenant: tenant,
      name: "Revisor",
      axis: "vertical",
      position: 200,
      permissions: { "captacoes" => { "review" => true } }
    )
    other_reviewer_profile = Profile.create!(
      tenant: other_tenant,
      name: "Revisor",
      axis: "vertical",
      position: 200,
      permissions: { "captacoes" => { "review" => true } }
    )
    reviewer = create(:admin_user, tenant: tenant, profile: reviewer_profile, active: true)
    other_reviewer = create(:admin_user, tenant: other_tenant, profile: other_reviewer_profile, active: true)
    habitation = create(:habitation, tenant: tenant, codigo: "CAP-REVIEW-1", intake_origin: Habitation::INTAKE_ORIGIN_BROKER)
    property_setting = instance_double(
      PropertySetting,
      notify_internal_review_events: true,
      notify_email_review_events: false
    )

    allow(Notifications::PushDispatcher).to receive(:deliver)

    described_class.new(
      habitation: habitation,
      actor: reviewer,
      event: "submit_for_review",
      property_setting: property_setting
    ).call

    expect(Notifications::PushDispatcher).to have_received(:deliver).with(
      hash_including(admin_user_id: reviewer.id)
    )
    expect(Notifications::PushDispatcher).not_to have_received(:deliver).with(
      hash_including(admin_user_id: other_reviewer.id)
    )
  end
end
