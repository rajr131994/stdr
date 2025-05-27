class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  def encryption_key
    Rails.application.credentials.production[:attr_encrypted_key]
  end
end
