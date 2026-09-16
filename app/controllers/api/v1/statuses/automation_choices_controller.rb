# frozen_string_literal: true

class Api::V1::Statuses::AutomationChoicesController < Api::BaseController
  include Authorization

  before_action -> { doorkeeper_authorize! :write, :'write:statuses' }
  before_action :require_user!
  before_action :set_status

  def create
    raise Mastodon::NotPermittedError if @status.account_id == current_account.id
    raise Mastodon::NotPermittedError unless @status.account.local? && @status.account.user&.functional?

    card = @status.status_automation_card
    raise ActiveRecord::RecordNotFound if card.nil?

    choice = card.choices.find(params[:choice_id])
    card.with_lock do
      raise Mastodon::ValidationError if card.executions.exists?(selected_by_account: current_account)

      choice = AutomationResponseSelector.random_variant(
        card.choices,
        selected_choice: choice,
        seed: "status:#{card.id}:#{current_account.id}"
      )

      direct_conversation = AccountConversation.where(account: @status.account, participant_account_ids: [current_account.id]).order(last_status_id: :desc).first
      response_text = [choice.response_text, choice.image_url].compact_blank.join("\n\n")
      response_status = PostStatusService.new.call(
        @status.account,
        text: response_text,
        thread: direct_conversation&.last_status,
        visibility: :direct,
        hidden_mentions: [current_account],
        allowed_mentions: [current_account.id],
        idempotency: "status-automation-#{card.id}-#{current_account.id}"
      )

      account_conversation = AccountConversation.add_status(@status.account, response_status)
      ensure_direct_memberships!(account_conversation.conversation)
      AccountConversation.add_status(current_account, response_status)
      card.executions.create!(
        status_automation_choice: choice,
        selected_by_account: current_account,
        response_status: response_status
      )
      @response_status = response_status
    end

    render json: @response_status, serializer: REST::StatusSerializer
  end

  private

  def set_status
    @status = Status.find(params[:status_id])
    authorize @status, :show?
  rescue ActiveRecord::RecordNotFound, Mastodon::NotPermittedError
    not_found
  end

  def ensure_direct_memberships!(conversation)
    return if conversation.conversation_memberships.exists?

    conversation.conversation_memberships.create!(account: @status.account, role: :owner)
    conversation.conversation_memberships.create!(account: current_account, role: :member)
  end
end
