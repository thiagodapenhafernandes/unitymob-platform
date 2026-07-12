class PhotographyScheduleBlock < ApplicationRecord
  include TenantScoped
  belongs_to :created_by, class_name: "AdminUser", optional: true

  validates :date, presence: true, uniqueness: { scope: :tenant_id }
end
