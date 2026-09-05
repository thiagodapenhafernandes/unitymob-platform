class SupportNotificationRead < ActiveRecord::Base
  belongs_to :staff
  belongs_to :ticket, class_name: 'Support::Ticket'
end
