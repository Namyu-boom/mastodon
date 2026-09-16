# frozen_string_literal: true

class ConversationMembership < ApplicationRecord
  belongs_to :conversation
  belongs_to :account

  enum :role, { member: 0, owner: 1 }

  scope :active, -> { where(active: true) }

  validates :account_id, uniqueness: { scope: :conversation_id }
end
