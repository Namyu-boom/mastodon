# frozen_string_literal: true

class Api::V1::ConversationAutomationRulesController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:statuses' }, only: [:index, :show]
  before_action -> { doorkeeper_authorize! :write, :'write:conversations' }, except: [:index, :show]
  before_action :require_user!
  before_action :set_rule, only: [:show, :update, :destroy]

  def index
    render json: current_account.conversation_automation_rules.order(id: :desc), each_serializer: REST::ConversationAutomationRuleManagementSerializer
  end

  def show
    render json: @rule, serializer: REST::ConversationAutomationRuleManagementSerializer
  end

  def create
    @rule = current_account.conversation_automation_rules.create!(rule_params)
    render json: @rule, serializer: REST::ConversationAutomationRuleManagementSerializer, status: 201
  end

  def update
    @rule.update!(rule_params)
    render json: @rule, serializer: REST::ConversationAutomationRuleManagementSerializer
  end

  def destroy
    @rule.destroy!
    render_empty
  end

  private

  def set_rule
    @rule = current_account.conversation_automation_rules.find(params[:id])
  end

  def rule_params
    params.permit(:name, :prompt, :active, :trigger_keyword, :match_in_text, :default_response_text, :default_image_url, choices_attributes: [:id, :label, :response_text, :image_url, :position, :_destroy])
  end
end
