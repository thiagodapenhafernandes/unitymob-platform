class Support::Account < ActiveRecord::Base
  self.table_name = "support_accounts"
  encrypts :secret
  has_many :tickets, class_name: "Support::Ticket", dependent: :restrict_with_exception
  validates :uid, :name, :secret, :endpoint, presence: true
  validates :secret, length: { minimum: 32 }
  validate :secure_endpoint

  def self.valid_endpoint?(endpoint)
    uri = URI.parse(endpoint.to_s)
    scheme = uri.scheme == "https" || (!Rails.env.production? && uri.scheme == "http" && %w[127.0.0.1 localhost].include?(uri.host))
    scheme && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && [nil, "", "/"].include?(uri.path)
  rescue URI::InvalidURIError
    false
  end

  private

  def secure_endpoint
    errors.add(:endpoint, "deve ser a origem HTTPS da aplicação") unless self.class.valid_endpoint?(endpoint)
  end
end
