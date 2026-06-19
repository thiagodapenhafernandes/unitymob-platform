require "rails_helper"

RSpec.describe AdminUser, "Admin do Sistema", type: :model do
  it "system_admin? reflete a flag super_admin" do
    expect(build(:admin_user, super_admin: true).system_admin?).to be(true)
    expect(build(:admin_user, super_admin: false).system_admin?).to be(false)
  end

  it "super_admin é admin? mesmo sem role admin nem profile admin" do
    user = build(:admin_user, role: :editor, profile: nil, super_admin: true)
    expect(user.admin?).to be(true)
  end

  it "usuário comum (sem flags) não é admin nem system_admin" do
    user = build(:admin_user, role: :editor, profile: nil, super_admin: false)
    expect(user.admin?).to be_falsey
    expect(user.system_admin?).to be(false)
  end

  it "operador (super_admin) fica fora das listas da conta" do
    member = create(:admin_user, super_admin: false, active: true)
    op     = create(:admin_user, super_admin: true, active: true)

    expect(AdminUser.account_members).to include(member)
    expect(AdminUser.account_members).not_to include(op)
    expect(AdminUser.active).not_to include(op)        # some dos dropdowns .active
    expect(AdminUser.displayed_on_site).not_to include(op)
  end
end
