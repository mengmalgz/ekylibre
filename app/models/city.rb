class City < ActiveRecord::Base
  belongs_to :company
  belongs_to :district
  has_many :areas

  attr_readonly :company_id
  #validates_format_of :insee_ar, :with=>/\d/
  #validates_format_of :insee_ct, :with=>/\d{2}/
  #validates_format_of :insee_reg, :with=>/\d{2}/
  #validates_format_of :insee_com, :with=>/\d{3}/
 
end
