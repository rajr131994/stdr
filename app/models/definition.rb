class Definition < ApplicationRecord
  belongs_to :deftype
  has_many :def_lines
end
