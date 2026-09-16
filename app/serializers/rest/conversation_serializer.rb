# frozen_string_literal: true

class REST::ConversationSerializer < ActiveModel::Serializer
  attributes :id, :unread, :title, :owner_id

  has_many :participant_accounts, key: :accounts, serializer: REST::AccountSerializer
  has_one :last_status, serializer: REST::StatusSerializer

  def id
    object.id.to_s
  end

  def title
    object.conversation.title
  end

  def owner_id
    object.conversation.parent_account_id&.to_s
  end
end
