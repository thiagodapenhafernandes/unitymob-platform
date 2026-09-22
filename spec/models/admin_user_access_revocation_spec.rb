require "rails_helper"

RSpec.describe AdminUser, "#revoke_all_access!", type: :model do
  it "revoga tokens, aparelhos, push e check-in do usuario" do
    user = create(:admin_user)
    user.update!(remember_created_at: 1.day.ago)
    old_jti = user.jti
    PushSubscription.create!(admin_user: user, endpoint: "https://web.push.apple.com/revoke", p256dh: "p256dh", auth: "auth", active: true)
    BrowserExtensionGrant.create!(
      tenant: user.tenant,
      admin_user: user,
      extension_id: "a" * 32,
      challenge_digest: BrowserExtensionGrant.digest("challenge"),
      challenge_expires_at: 5.minutes.from_now,
      expires_at: 1.day.from_now
    )
    device = create(:trusted_device, tenant: user.tenant, admin_user: user, status: "trusted")
    check_in = create(:check_in, tenant: user.tenant, admin_user: user, store: create(:store, tenant: user.tenant), status: :active)

    user.revoke_all_access!

    user.reload
    expect(user.jti).not_to eq(old_jti)
    expect(user.remember_created_at).to be_nil
    expect(user.session_revoked_at).to be_present if user.has_attribute?(:session_revoked_at)
    expect(PushSubscription.where(admin_user: user).pluck(:active)).to eq([false])
    expect(BrowserExtensionGrant.where(admin_user: user).pluck(:revoked_at)).to all(be_present)
    expect(TrustedDevice.exists?(device.id)).to be(false)
    expect(check_in.reload).to be_closed_admin_force
  end

  it "marca usuario inativo como nao autenticavel" do
    user = create(:admin_user, active: false)

    expect(user.active_for_authentication?).to be(false)
    expect(user.inactive_message).to eq(:inactive)
  end

  it "libera notificacao apenas para telefones na allowlist quando a flag local esta ligada" do
    old_enabled = ENV["NOTIFICATION_PHONE_ALLOWLIST_ENABLED"]
    old_numbers = ENV["NOTIFICATION_ALLOWED_PHONE_NUMBERS"]
    ENV["NOTIFICATION_PHONE_ALLOWLIST_ENABLED"] = "true"
    ENV["NOTIFICATION_ALLOWED_PHONE_NUMBERS"] = "21990872427,11999998888"
    allowed = create(:admin_user, phone: "(21) 99087-2427")
    blocked = create(:admin_user, phone: "(21) 90000-0000")

    expect(allowed.notification_delivery_allowed?).to be(true)
    expect(blocked.notification_delivery_allowed?).to be(false)
  ensure
    ENV["NOTIFICATION_PHONE_ALLOWLIST_ENABLED"] = old_enabled
    ENV["NOTIFICATION_ALLOWED_PHONE_NUMBERS"] = old_numbers
  end
end
