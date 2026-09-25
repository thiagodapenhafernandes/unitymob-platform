require "rails_helper"
require_relative "../../support/contract/shared_header_footer_examples"

RSpec.describe "contrato do cabeçalho e rodapé públicos", type: :helper do
  let(:header_standard_source) { Rails.root.join("app/views/layouts/_header.html.erb").read }
  let(:footer_standard_source) { Rails.root.join("app/views/layouts/_footer.html.erb").read }
  let(:header_luxury_source) { Rails.root.join("app/views/public_theme/components/_site_header.html.erb").read }
  let(:footer_luxury_source) { Rails.root.join("app/views/public_theme/components/_site_footer.html.erb").read }
  let(:shell_standard_source) { Rails.root.join("app/views/layouts/application.html.erb").read }
  let(:shell_luxury_source) { Rails.root.join("app/views/public_theme/_luxury_shell.html.erb").read }

  it_behaves_like "contrato do cabeçalho e rodapé públicos"
end
