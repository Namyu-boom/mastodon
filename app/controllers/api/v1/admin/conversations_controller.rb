# frozen_string_literal: true

class Api::V1::Admin::ConversationsController < Api::BaseController
  include AccountableConcern

  LIMIT = 20

  before_action -> { doorkeeper_authorize! :read, :'read:statuses' }
  before_action :require_user!
  before_action :require_administrator!
  before_action :set_conversation, only: :show
  after_action :insert_pagination_headers, only: :index
  after_action :insert_status_pagination_headers, only: :show

  def index
    @conversations = Conversation.joins(:statuses)
      .merge(Status.direct_visibility)
      .distinct
      .order(id: :desc)
      .to_a_paginated_by_id(limit_param(LIMIT), params_slice(:max_id, :since_id, :min_id))

    current_account.action_logs.create!(action: :view_direct_messages)
    render json: @conversations, each_serializer: REST::Admin::ConversationSerializer
  end

  def show
    @statuses = preload_collection_paginated_by_id(
      @conversation.statuses.direct_visibility.order(id: :desc),
      Status,
      limit_param(DEFAULT_STATUSES_LIMIT),
      params_slice(:max_id, :since_id, :min_id)
    )
    log_action :view_direct_message, @conversation
    render json: @statuses, each_serializer: REST::StatusSerializer, relationships: StatusRelationshipsPresenter.new(@statuses, current_account.id)
  end

  private

  def require_administrator!
    raise Mastodon::NotPermittedError unless current_user.can?(:administrator)
  end

  def set_conversation
    @conversation = Conversation.joins(:statuses).merge(Status.direct_visibility).distinct.find(params[:id])
  end

  def insert_status_pagination_headers
    next_path = api_v1_admin_conversation_url(@conversation, pagination_params(max_id: @statuses.last.id)) if @statuses.size == limit_param(DEFAULT_STATUSES_LIMIT)
    prev_path = api_v1_admin_conversation_url(@conversation, pagination_params(min_id: @statuses.first.id)) unless @statuses.empty?
    set_pagination_headers(next_path, prev_path)
  end

  def next_path
    api_v1_admin_conversations_url pagination_params(max_id: pagination_max_id) if records_continue?
  end

  def prev_path
    api_v1_admin_conversations_url pagination_params(min_id: pagination_since_id) unless @conversations.empty?
  end

  def pagination_collection
    @conversations
  end

  def records_continue?
    @conversations.size == limit_param(LIMIT)
  end
end
