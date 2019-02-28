class Category < ApplicationRecord
  has_many :children, class_name: 'Category', foreign_key: 'parent_id'
  belongs_to :parent, class_name: 'Category', optional: true
  has_and_belongs_to_many :words

  validates :name, presence: true, uniqueness: true
end