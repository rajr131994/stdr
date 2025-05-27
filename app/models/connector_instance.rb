class ConnectorInstance < ApplicationRecord
  validates_uniqueness_of :id

  after_create :create_tenant
  after_destroy :drop_tenant

  private

  def create_tenant()
    puts '-----create tenant---'
    response = Apartment::Tenant.create(self.id)
  end

  def drop_tenant
    puts '-----drop tenantttt---'
    response = Apartment::Tenant.drop(self.id)
  end
end
