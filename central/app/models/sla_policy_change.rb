class SlaPolicyChange < ActiveRecord::Base
  belongs_to :staff
  def readonly? = persisted?
end
