class SeedDefaultPublicForms < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:tenants) && table_exists?(:public_forms)

    say_with_time "Creating default public property announcement forms" do
      Tenant.find_each do |tenant|
        PublicForm.ensure_default_site_forms!(tenant: tenant)
      end
    end
  end

  def down
    return unless table_exists?(:public_forms)

    PublicForm.where(slug: PublicForm::DEFAULT_ANNOUNCE_SLUG).find_each do |form|
      form.destroy unless form.submissions.exists?
    end
  end
end
