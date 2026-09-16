# frozen_string_literal: true

# == Schema Information
#
# Table name: conversations
#
#  id                :bigint(8)        not null, primary key
#  uri               :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  parent_account_id :bigint(8)
#  parent_status_id  :bigint(8)
#

class Conversation < ApplicationRecord
  validates :uri, uniqueness: true, if: :uri?
  validates :title, length: { maximum: 100 }, allow_nil: true

  has_many :statuses, dependent: nil
  has_many :conversation_memberships, dependent: :destroy
  has_many :conversation_automation_executions, dependent: :destroy
  has_many :member_accounts, through: :conversation_memberships, source: :account

  belongs_to :parent_status, class_name: 'Status', optional: true, inverse_of: :owned_conversation
  belongs_to :parent_account, class_name: 'Account', optional: true

  scope :local, -> { where(uri: nil) }

  before_validation :set_parent_account, on: :create

  def to_param
    "#{parent_account_id}-#{parent_status_id}" unless parent_account_id.nil? || parent_status_id.nil?
  end

  def local?
    uri.nil?
  end

  def object_type
    :conversation
  end

  def active_member_accounts
    Account.joins(:conversation_memberships).merge(conversation_memberships.active)
  end

  private

  def set_parent_account
    self.parent_account = parent_status.account if parent_status.present?
  end
end
