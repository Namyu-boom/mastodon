# frozen_string_literal: true

class Api::V1::ConversationsController < Api::BaseController
  LIMIT = 20
  PARTICIPANTS_LIMIT = 20

  before_action -> { doorkeeper_authorize! :read, :'read:statuses' }, only: [:index, :show, :info, :automation_choices]
  before_action -> { doorkeeper_authorize! :write, :'write:conversations' }, except: [:index, :show, :info, :automation_choices]
  before_action :require_user!
  before_action :set_conversation, except: [:index, :create]
  after_action :insert_pagination_headers, only: :index
  after_action :insert_status_pagination_headers, only: :show

  def index
    @conversations = paginated_conversations
    render json: @conversations, each_serializer: REST::ConversationSerializer, relationships: StatusRelationshipsPresenter.new(@conversations.map(&:last_status), current_user&.account_id)
  end

  def show
    @statuses = paginated_statuses
    render json: @statuses, each_serializer: REST::StatusSerializer, relationships: StatusRelationshipsPresenter.new(@statuses, current_user&.account_id)
  end

  def info
    render json: @conversation, serializer: REST::ConversationSerializer
  end

  def automation_choices
    ensure_memberships!
    last_sender_status = @conversation.conversation.statuses.where(account: current_account).order(id: :desc).first
    rules = if last_sender_status.nil?
              []
            else
              ConversationAutomationTriggerService.new
                .matching_rules(conversation: @conversation.conversation, sender: current_account, text: last_sender_status.text, seed: last_sender_status.id)
                .select { |rule| rule.choices.any? }
            end

    render json: rules, each_serializer: REST::ConversationAutomationRuleSerializer
  end

  def select_automation_choice
    ensure_memberships!
    conversation = @conversation.conversation
    last_sender_status = conversation.statuses.where(account: current_account).order(id: :desc).first
    raise ActiveRecord::RecordNotFound if last_sender_status.nil?

    member_ids = conversation.conversation_memberships.active.where.not(account: current_account).pluck(:account_id)
    choice = ConversationAutomationChoice.joins(:conversation_automation_rule)
      .merge(ConversationAutomationRule.active.where(account_id: member_ids))
      .find(params[:choice_id])
    raise ActiveRecord::RecordNotFound unless ConversationAutomationTriggerService.new.matches?(choice.conversation_automation_rule, last_sender_status.text)
    raise Mastodon::NotPermittedError unless choice.conversation_automation_rule.account.user&.functional?
    raise Mastodon::ValidationError if ConversationAutomationExecution.exists?(conversation:, conversation_automation_rule: choice.conversation_automation_rule, selected_by_account: current_account)

    triggered_rule_ids = ConversationAutomationTriggerService.new
      .matching_rules(conversation:, sender: current_account, text: last_sender_status.text, seed: last_sender_status.id)
      .map(&:id)
    raise ActiveRecord::RecordNotFound unless triggered_rule_ids.include?(choice.conversation_automation_rule_id)

    conversation.with_lock do
      raise Mastodon::ValidationError if ConversationAutomationExecution.exists?(conversation: conversation, conversation_automation_rule: choice.conversation_automation_rule, selected_by_account: current_account)

      choice = AutomationResponseSelector.random_variant(
        choice.conversation_automation_rule.choices,
        selected_choice: choice,
        seed: "conversation:#{conversation.id}:#{choice.conversation_automation_rule_id}:#{current_account.id}:#{last_sender_status.id}"
      )

      recipients = conversation.active_member_accounts.where.not(id: choice.conversation_automation_rule.account_id).to_a
      response_text = [choice.response_text, choice.image_url].compact_blank.join("\n\n")
      status = PostStatusService.new.call(
        choice.conversation_automation_rule.account,
        text: response_text,
        thread: conversation.statuses.order(id: :desc).first,
        visibility: :direct,
        hidden_mentions: recipients,
        allowed_mentions: recipients.map(&:id),
        idempotency: "conversation-automation-#{conversation.id}-#{choice.conversation_automation_rule_id}-#{current_account.id}"
      )

      sync_status_for_members!(conversation, status)
      ConversationAutomationExecution.create!(
        conversation: conversation,
        conversation_automation_rule: choice.conversation_automation_rule,
        conversation_automation_choice: choice,
        selected_by_account: current_account,
        response_status: status
      )
      @status = status
    end

    render json: @status, serializer: REST::StatusSerializer
  end

  def create
    accounts = conversation_accounts
    status = PostStatusService.new.call(
      current_account,
      text: message_params[:status],
      visibility: :direct,
      hidden_mentions: accounts,
      allowed_mentions: accounts.map(&:id),
      application: doorkeeper_token.application,
      idempotency: request.headers['Idempotency-Key'],
      with_rate_limit: true
    )

    @conversation = AccountConversation.add_status(current_account, status)
    create_memberships!(@conversation.conversation, accounts)
    sync_status_for_members!(@conversation.conversation, status)
    trigger_automatic_responses!(@conversation.conversation, status)
    render json: @conversation, serializer: REST::ConversationSerializer, relationships: StatusRelationshipsPresenter.new([status], current_account.id), status: 201
  end

  def update
    authorize_conversation_owner!
    @conversation.conversation.update!(title: params[:title].presence)
    render json: @conversation, serializer: REST::ConversationSerializer
  end

  def participants
    authorize_conversation_owner!
    ensure_memberships!

    accounts = requested_accounts
    active_count = @conversation.conversation.conversation_memberships.active.count
    new_count = accounts.count { |account| !@conversation.conversation.conversation_memberships.active.exists?(account: account) }
    raise Mastodon::ValidationError if active_count + new_count > PARTICIPANTS_LIMIT + 1

    accounts.each do |account|
      membership = @conversation.conversation.conversation_memberships.find_or_initialize_by(account: account)
      membership.update!(active: true, role: :member)
    end
    sync_participant_caches!

    render json: @conversation, serializer: REST::ConversationSerializer
  end

  def leave
    ensure_memberships!
    membership = @conversation.conversation.conversation_memberships.active.find_by!(account: current_account)
    raise Mastodon::NotPermittedError if membership.owner?

    membership.update!(active: false)
    sync_participant_caches!
    @conversation.destroy!
    render_empty
  end

  def messages
    @status = PostStatusService.new.call(
      current_account,
      text: message_params[:status],
      thread: @conversation.last_status,
      visibility: :direct,
      sensitive: message_params[:sensitive],
      spoiler_text: message_params[:spoiler_text],
      language: message_params[:language],
      hidden_mentions: message_recipients,
      application: doorkeeper_token.application,
      idempotency: request.headers['Idempotency-Key'],
      with_rate_limit: true
    )

    sync_status_for_members!(@conversation.conversation, @status)
    trigger_automatic_responses!(@conversation.conversation, @status)

    render json: @status, serializer: REST::StatusSerializer
  end

  def read
    @conversation.update!(unread: false)
    render json: @conversation, serializer: REST::ConversationSerializer
  end

  def unread
    @conversation.update!(unread: true)
    render json: @conversation, serializer: REST::ConversationSerializer
  end

  def destroy
    @conversation.destroy!
    render_empty
  end

  private

  def set_conversation
    @conversation = AccountConversation.where(account: current_account).find(params[:id])
  end

  def message_params
    params.permit(:status, :sensitive, :spoiler_text, :language)
  end

  def conversation_accounts
    account_ids = Array(params.permit(account_ids: [])[:account_ids]).map(&:to_i).uniq
    raise Mastodon::ValidationError if account_ids.empty? || account_ids.size > PARTICIPANTS_LIMIT || account_ids.include?(current_account.id)

    accounts = Account.where(id: account_ids).to_a
    raise Mastodon::ValidationError unless accounts.size == account_ids.size

    accounts
  end

  def requested_accounts
    account_ids = Array(params.permit(account_ids: [])[:account_ids]).map(&:to_i).uniq
    raise Mastodon::ValidationError if account_ids.empty? || account_ids.include?(current_account.id)

    accounts = Account.where(id: account_ids).to_a
    raise Mastodon::ValidationError unless accounts.size == account_ids.size

    accounts
  end

  def create_memberships!(conversation, accounts)
    conversation.conversation_memberships.create!(account: current_account, role: :owner)
    accounts.each { |account| conversation.conversation_memberships.create!(account: account, role: :member) }
  end

  def ensure_memberships!
    conversation = @conversation.conversation
    return if conversation.conversation_memberships.exists?

    account_ids = (@conversation.participant_account_ids + [current_account.id]).uniq
    account_ids.each do |account_id|
      role = account_id == conversation.parent_account_id ? :owner : :member
      conversation.conversation_memberships.create!(account_id: account_id, role: role)
    end
  end

  def authorize_conversation_owner!
    ensure_memberships!
    membership = @conversation.conversation.conversation_memberships.active.find_by(account: current_account)
    raise Mastodon::NotPermittedError unless membership&.owner?
  end

  def message_recipients
    ensure_memberships!
    membership = @conversation.conversation.conversation_memberships.active.find_by(account: current_account)
    raise Mastodon::NotPermittedError if membership.nil?

    @conversation.conversation.active_member_accounts.where.not(id: current_account.id).to_a
  end

  def sync_participant_caches!
    conversation = @conversation.conversation
    member_ids = conversation.conversation_memberships.active.pluck(:account_id)

    AccountConversation.where(conversation: conversation).find_each do |account_conversation|
      account_conversation.update!(participant_account_ids: member_ids - [account_conversation.account_id])
    end
  end

  def trigger_automatic_responses!(conversation, status)
    ConversationAutomationTriggerService.new.call(conversation:, sender: current_account, status:)
  end

  def sync_status_for_members!(conversation, status)
    conversation.active_member_accounts.find_each do |account|
      AccountConversation.add_status(account, status)
    end
  end

  def paginated_conversations
    AccountConversation.where(account: current_account)
      .includes(
        account: [:account_stat, user: :role],
        last_status: [
          :media_attachments,
          :status_stat,
          :tags,
          {
            preview_cards_status: { preview_card: { author_account: [:account_stat, user: :role] } },
            active_mentions: :account,
            account: [:account_stat, user: :role],
          },
        ]
      )
      .to_a_paginated_by_id(limit_param(LIMIT), params_slice(:max_id, :since_id, :min_id))
  end

  def paginated_statuses
    scope = Status.where(id: @conversation.status_ids).reorder(id: :desc)
    preload_collection_paginated_by_id(scope, Status, limit_param(DEFAULT_STATUSES_LIMIT), params_slice(:max_id, :since_id, :min_id))
  end

  def insert_status_pagination_headers
    set_pagination_headers(statuses_next_path, statuses_prev_path)
  end

  def statuses_next_path
    api_v1_conversation_url(@conversation, pagination_params(max_id: @statuses.last.id)) if @statuses.size == limit_param(DEFAULT_STATUSES_LIMIT)
  end

  def statuses_prev_path
    api_v1_conversation_url(@conversation, pagination_params(min_id: @statuses.first.id)) unless @statuses.empty?
  end

  def next_path
    api_v1_conversations_url pagination_params(max_id: pagination_max_id) if records_continue?
  end

  def prev_path
    api_v1_conversations_url pagination_params(min_id: pagination_since_id) unless @conversations.empty?
  end

  def pagination_max_id
    @conversations.last.last_status_id
  end

  def pagination_since_id
    @conversations.first.last_status_id
  end

  def records_continue?
    @conversations.size == limit_param(LIMIT)
  end
end
