require "rails_helper"

RSpec.describe "Admin permission gate coverage", type: :request do
  GATE_PATTERN = /
    requires_permission|
    check_permission!|
    check_any_permission!|
    require_system_admin!|
    require_admin_or_administrative_user!|
    require_dashboard_admin!|
    authorize_duplicate_check!|
    require_meta_integration_permission!
  /x

  it "mantém controllers admin operacionais protegidos ou explicitamente isentos" do
    controller_files = Dir.glob(Rails.root.join("app/controllers/admin/**/*_controller.rb"))
      .map { |path| Pathname(path).relative_path_from(Rails.root).to_s }

    ungated = controller_files.reject do |file|
      Rails.root.join(file).read.match?(GATE_PATTERN)
    end

    expect(ungated).to match_array(Admin::BaseController::PERMISSION_GATE_EXEMPT_CONTROLLER_FILES.keys)
  end
end
