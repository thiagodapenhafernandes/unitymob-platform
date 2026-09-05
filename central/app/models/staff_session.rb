class StaffSession < ActiveRecord::Base
  belongs_to :staff
  has_many :presence_windows, class_name: 'StaffPresenceWindow'
  LEASE = 75.seconds
  def live? = ended_at.nil? && expires_at.future?
  def online? = live? && last_seen_at && last_seen_at >= LEASE.ago

  def heartbeat!
    with_lock do
      return unless live?
      now = Time.current
      window = presence_windows.order(:id).last
      if window && window.confirmed_until >= now - LEASE
        window.update!(confirmed_until: now)
      else
        presence_windows.create!(started_at: now, confirmed_until: now)
      end
      update!(last_seen_at: now)
    end
  end

  def finish!(reason)
    with_lock { update!(ended_at: Time.current, end_reason: reason) unless ended_at }
  end

  def self.expire!
    where(ended_at: nil).where('expires_at <= ?', Time.current).update_all('ended_at = expires_at, end_reason = \'expired\'')
  end
end
