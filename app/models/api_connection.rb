class ApiConnection < ApplicationRecord

  attr_encrypted :password, key: :encryption_key

end