# = Informations
#
# == License
#
# Ekylibre - Simple ERP
# Copyright (C) 2009-2012 Brice Texier, Thibaud Merigon
# Copyright (C) 2012-2014 Brice Texier, David Joulin
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
#
# == Table: gaps
#
#  accounted_at     :datetime
#  affair_id        :integer          not null
#  amount           :decimal(19, 4)   default(0.0), not null
#  created_at       :datetime         not null
#  creator_id       :integer
#  currency         :string(3)        not null
#  direction        :string(255)      not null
#  entity_id        :integer          not null
#  entity_role      :string(255)      not null
#  id               :integer          not null, primary key
#  journal_entry_id :integer
#  lock_version     :integer          default(0), not null
#  number           :string(255)      not null
#  pretax_amount    :decimal(19, 4)   default(0.0), not null
#  printed_at       :datetime         not null
#  updated_at       :datetime         not null
#  updater_id       :integer
#


class Gap < Ekylibre::Record::Base
  enumerize :direction, in: [:profit, :loss], predicates: true
  enumerize :entity_role, in: [:client, :supplier], predicates: true
  belongs_to :journal_entry
  belongs_to :entity
  has_many :items, class_name: "GapItem", inverse_of: :gap

  #[VALIDATORS[ Do not edit these lines directly. Use `rake clean:validations`.
  validates_numericality_of :amount, :pretax_amount, allow_nil: true
  validates_length_of :currency, allow_nil: true, maximum: 3
  validates_length_of :direction, :entity_role, :number, allow_nil: true, maximum: 255
  validates_presence_of :affair, :amount, :currency, :direction, :entity, :entity_role, :number, :pretax_amount, :printed_at
  #]VALIDATORS]

  accepts_nested_attributes_for :items
  acts_as_numbered
  acts_as_affairable :entity, debit: :loss?, role: :entity_role, good: :profit?
  alias_attribute :label, :number

  before_validation do
    self.printed_at ||= Time.now
  end

  bookkeep do |b|
    b.journal_entry(Journal.used_for_gaps, printed_at: self.printed_at, :unless => self.amount.zero?) do |entry|
      label = tc(:bookkeep, resource: self.direction.text, number: self.number, entity: self.entity.full_name)
      if self.profit?
        entry.add_debit(label, self.entity.account(self.entity_role).id, self.amount)
        for item in self.items
          entry.add_credit(label, Account.find_or_create_in_chart(:other_usual_running_profits), item.pretax_amount)
          entry.add_credit(label, item.tax.collect_account_id, item.taxes_amount)
        end
      else
        entry.add_credit(label, self.entity.account(self.entity_role).id, self.amount)
        for item in self.items
          entry.add_debit(label, Account.find_or_create_in_chart(:other_usual_running_expenses), item.pretax_amount)
          entry.add_debit(label, item.tax.deduction_account_id, item.taxes_amount)
        end
      end
    end
  end

  # Gives the amount to use for affair bookkeeping
  def deal_amount
    return (self.loss? ? -self.amount : self.amount)
  end

end
