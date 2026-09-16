# frozen_string_literal: true

class ConversationAutomationTriggerService < BaseService
  def call(conversation:, sender:, status:)
    matching_rules(conversation:, sender:, text: status.text, seed: status.id).each do |rule|
      next if rule.choices.exists?

      execute_default_response!(conversation, sender, status, rule)
    end
  end

  def matching_rules(conversation:, sender:, text:, seed:)
    member_ids = conversation.conversation_memberships.active.where.not(account: sender).pluck(:account_id)
    executed_rule_ids = ConversationAutomationExecution.where(conversation:, selected_by_account: sender).select(:conversation_automation_rule_id)
    executed_group_keys = ConversationAutomationRule.where(id: executed_rule_ids).pluck(:account_id, :trigger_keyword).map do |account_id, keyword|
      [account_id, AutomationResponseSelector.normalized_key(keyword)]
    end

    matching = ConversationAutomationRule.active
      .where(account_id: member_ids)
      .where.not(id: executed_rule_ids)
      .includes(:choices)
      .select { |rule| matches?(rule, text) }
      .reject { |rule| executed_group_keys.include?([rule.account_id, AutomationResponseSelector.normalized_key(rule.trigger_keyword)]) }

    matching
      .group_by { |rule| [rule.account_id, AutomationResponseSelector.normalized_key(rule.trigger_keyword)] }
      .map do |group_key, rules|
        AutomationResponseSelector.stable_sample(rules, seed: "#{conversation.id}:#{sender.id}:#{seed}:#{group_key.join(':')}")
      end
  end

  def matches?(rule, text)
    token = Regexp.escape(rule.trigger_keyword.strip)
    expression = rule.match_in_text? ? /\[\s*#{token}\s*\]/i : /\A\s*\[\s*#{token}\s*\]\s*\z/i
    text.match?(expression)
  end

  private

  def execute_default_response!(conversation, sender, trigger_status, rule)
    conversation.with_lock do
      return if ConversationAutomationExecution.exists?(conversation:, conversation_automation_rule: rule, selected_by_account: sender)
      return unless rule.account.user&.functional?

      recipients = conversation.active_member_accounts.where.not(id: rule.account_id).to_a
      response_text = [rule.default_response_text, rule.default_image_url].compact_blank.join("\n\n")
      response_status = PostStatusService.new.call(
        rule.account,
        text: response_text,
        thread: trigger_status,
        visibility: :direct,
        hidden_mentions: recipients,
        allowed_mentions: recipients.map(&:id),
        idempotency: "conversation-trigger-#{conversation.id}-#{rule.id}-#{sender.id}"
      )

      conversation.active_member_accounts.find_each do |account|
        AccountConversation.add_status(account, response_status)
      end
      ConversationAutomationExecution.create!(
        conversation:,
        conversation_automation_rule: rule,
        selected_by_account: sender,
        response_status:
      )
    end
  end
end
