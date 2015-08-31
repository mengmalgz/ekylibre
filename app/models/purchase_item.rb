# = Informations
#
# == License
#
# Ekylibre - Simple agricultural ERP
# Copyright (C) 2008-2009 Brice Texier, Thibaud Merigon
# Copyright (C) 2010-2012 Brice Texier
# Copyright (C) 2012-2015 Brice Texier, David Joulin
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
#
# == Table: purchase_items
#
#  account_id           :integer          not null
#  accounted_at         :datetime
#  amount               :decimal(19, 4)   default(0.0), not null
#  annotation           :text
#  created_at           :datetime         not null
#  creator_id           :integer
#  currency             :string           not null
#  fixed                :boolean          default(FALSE), not null
#  id                   :integer          not null, primary key
#  invoiced_at          :datetime
#  label                :text
#  lock_version         :integer          default(0), not null
#  position             :integer
#  pretax_amount        :decimal(19, 4)   default(0.0), not null
#  purchase_id          :integer          not null
#  quantity             :decimal(19, 4)   default(1.0), not null
#  reduction_percentage :decimal(19, 4)   default(0.0), not null
#  tax_id               :integer          not null
#  unit_amount          :decimal(19, 4)   default(0.0), not null
#  unit_pretax_amount   :decimal(19, 4)   not null
#  updated_at           :datetime         not null
#  updater_id           :integer
#  variant_id           :integer          not null
#

class PurchaseItem < Ekylibre::Record::Base
  include PeriodicCalculable
  refers_to :currency
  belongs_to :account
  belongs_to :purchase, inverse_of: :items
  belongs_to :variant, class_name: 'ProductNatureVariant', inverse_of: :purchase_items
  belongs_to :tax
  has_many :delivery_items, class_name: 'IncomingDeliveryItem', foreign_key: :purchase_item_id
  has_many :products, through: :delivery_items
  has_one :fixed_asset, foreign_key: :purchase_item_id, inverse_of: :purchase_item
  # [VALIDATORS[ Do not edit these lines directly. Use `rake clean:validations`.
  validates_datetime :accounted_at, :invoiced_at, allow_blank: true, on_or_after: Time.new(1, 1, 1, 0, 0, 0, '+00:00')
  validates_numericality_of :amount, :pretax_amount, :quantity, :reduction_percentage, :unit_amount, :unit_pretax_amount, allow_nil: true
  validates_inclusion_of :fixed, in: [true, false]
  validates_presence_of :account, :amount, :currency, :pretax_amount, :purchase, :quantity, :reduction_percentage, :tax, :unit_amount, :unit_pretax_amount, :variant
  # ]VALIDATORS]
  validates_length_of :currency, allow_nil: true, maximum: 3
  validates_presence_of :account, :tax, :reduction_percentage
  validates_associated :fixed_asset

  delegate :invoiced_at, :number, :computation_method, :computation_method_quantity_tax?, :computation_method_tax_quantity?, :computation_method_adaptative?, :computation_method_manual?, to: :purchase
  delegate :purchased?, :draft?, :order?, :supplier, to: :purchase
  delegate :currency, to: :purchase, prefix: true
  delegate :name, to: :variant, prefix: true
  delegate :name, :amount, :short_label, to: :tax, prefix: true
  # delegate :subscribing?, :deliverable?, to: :product_nature, prefix: true

  accepts_nested_attributes_for :fixed_asset

  alias_attribute :name, :label

  acts_as_list scope: :purchase
  sums :purchase, :items, :pretax_amount, :amount

  calculable period: :month, column: :pretax_amount, at: :invoiced_at, name: :sum

  # return all purchase items  between two dates
  scope :between, lambda { |started_at, stopped_at|
    joins(:purchase).merge(Purchase.invoiced_between(started_at, stopped_at))
  }
  # return all sale items for the consider product_nature
  scope :by_product_nature, lambda { |product_nature|
    joins(:variant).merge(ProductNatureVariant.of_natures(product_nature))
  }

  # return all sale items for the consider product_nature
  scope :by_product_nature_category, lambda { |product_nature_category|
    joins(:variant).merge(ProductNatureVariant.of_categories(product_nature_category))
  }

  before_validation do
    self.currency = purchase_currency if purchase

    self.quantity ||= 0
    self.reduction_percentage ||= 0

    if tax && unit_pretax_amount
      item = Nomen::Currency.find(currency)
      precision = item ? item.precision : 2
      self.unit_amount = unit_pretax_amount * (100.0 + tax_amount) / 100.0
      if pretax_amount.zero? || pretax_amount.nil?
        self.pretax_amount = (unit_pretax_amount * self.quantity * (100.0 - self.reduction_percentage) / 100.0).round(precision)
      end
      if amount.zero? || amount.nil?
        self.amount = (pretax_amount * (100.0 + tax_amount) / 100.0).round(precision)
      end
    end

    if purchase
      for replicated in [:accounted_at, :invoiced_at]
        send("#{replicated}=", purchase.send(replicated))
      end
    end

    if variant
      self.label ||= variant.commercial_name
      if fixed
        self.account = variant.fixed_asset_account || Account.find_in_nomenclature(:fixed_assets)
        unless fixed_asset
          # Create asset
          asset_attributes = {
            currency: currency,
            started_on: purchase.invoiced_at.to_date,
            depreciable_amount: pretax_amount,
            depreciation_method: variant.fixed_asset_depreciation_method,
            depreciation_percentage: variant.fixed_asset_depreciation_percentage,
            journal: Journal.find_by(nature: :various),
            allocation_account: variant.fixed_asset_allocation_account, # 28
            expenses_account: variant.fixed_asset_expenses_account # 68
          }
          if products.any?
            asset_attributes[:name] = delivery_items.collect(&:name).to_sentence
          end
          asset_attributes[:name] = name if asset_attributes[:name].blank?
          while FixedAsset.find_by(name: asset_attributes[:name])
            asset_attributes[:name] << ' ' + rand(FixedAsset.count * 36**3).to_s(36).upcase
          end
          build_fixed_asset(asset_attributes)
        end
      else
        self.account = variant.charge_account || Account.find_in_nomenclature(:expenses)
      end
    end
  end

  validate do
    errors.add(:currency, :invalid) if currency != purchase_currency if purchase
    errors.add(:quantity, :invalid) if self.quantity.zero?
  end

  def product_name
    variant.name
  end

  def taxes_amount
    amount - pretax_amount
  end

  def designation
    d = product_name
    d << "\n" + annotation.to_s unless annotation.blank?
    d << "\n" + tc(:tracking, serial: tracking.serial.to_s) if tracking
    d
  end

  def undelivered_quantity
    self.quantity - delivery_items.sum(:quantity)
  end

  # know how many percentage of invoiced VAT to declare
  def payment_ratio
    if purchase.affair.balanced?
      return 1.00
    elsif purchase.affair.debit != 0.0
      return (1 - (purchase.affair.balance / purchase.affair.debit)).to_f
    end
  end
end
