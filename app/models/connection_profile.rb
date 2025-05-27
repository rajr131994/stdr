class ConnectionProfile < ApplicationRecord
  attr_encrypted :password, key: :encryption_key
  attr_encrypted :client_secret_dest, key: :encryption_key
  attr_encrypted :client_secret_extract, key: :encryption_key
  validates_format_of :name, :on => :create, with: /\A[A-Za-z0-9_]+\z/, :message => 'no specials characters, only underscore and alphanumeric'

  has_many :destinations
  has_many :connection_profiles
end
