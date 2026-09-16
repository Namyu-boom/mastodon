# frozen_string_literal: true

class REST::Admin::ConversationSerializer < ActiveModel::Serializer
  attributes :id, :title, :created_at, :updated_at

  has_many :participant_accounts, key: :accounts, serializer: REST::AccountSerializer
  has_one :last_status, serializer: REST::StatusSerializer

  def id
    object.id.to_s
  end

  def participant_accounts
    if object.conversation_memberships.active.exists?
      object.active_member_accounts
    else
      account_ids = object.statuses.direct_visibility.joins(:active_mentions).pluck(:account_id, 'mentions.account_id').flatten.uniq
      Account.where(id: account_ids)
    end
  end

  def last_status
    object.statuses.direct_visibility.order(id: :desc).first
  end
end
