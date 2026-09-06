class BrowserExtensionOperation < ApplicationRecord
  belongs_to :browser_extension_grant
  validates :request_key, :request_digest, :result, presence: true
end
