class PhotographyScheduleBlock < ApplicationRecord
  belongs_to :created_by, class_name: "AdminUser", optional: true

  validates :date, presence: true, uniqueness: true
end
