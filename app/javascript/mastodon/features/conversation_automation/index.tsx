import { useCallback, useEffect, useState } from 'react';
import type { FormEvent } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';

import api from 'mastodon/api';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';

interface AutomationChoiceJSON {
  id: string;
  label: string;
  response_text: string;
  image_url: string | null;
  position: number;
}

interface AutomationRuleJSON {
  id: string;
  name: string;
  prompt: string;
  active: boolean;
  trigger_keyword: string;
  match_in_text: boolean;
  default_response_text: string | null;
  default_image_url: string | null;
  choices: AutomationChoiceJSON[];
}

interface ChoiceDraft {
  label: string;
  responseText: string;
  imageUrl: string;
}

const blankChoice = (): ChoiceDraft => ({ label: '', responseText: '', imageUrl: '' });

const messages = defineMessages({
  title: { id: 'messages.automation', defaultMessage: 'Automatic replies' },
  name: { id: 'automation.name', defaultMessage: 'Rule name' },
  prompt: { id: 'automation.prompt', defaultMessage: 'Question shown when choices exist (optional)' },
  keyword: { id: 'automation.keyword', defaultMessage: 'Keyword inside [brackets]' },
  matchInText: { id: 'automation.match_in_text', defaultMessage: 'Detect [keyword] inside a longer message' },
  defaultResponse: { id: 'automation.default_response', defaultMessage: 'Reply immediately when there are no choices' },
  defaultImage: { id: 'automation.default_image', defaultMessage: 'Default reply image URL (optional)' },
  randomHint: { id: 'automation.random_hint', defaultMessage: 'Repeat the same button label to add randomly selected response variants.' },
  choice: { id: 'automation.choice', defaultMessage: 'Keyword shown on the button' },
  response: { id: 'automation.response', defaultMessage: 'Message sent automatically' },
  image: { id: 'automation.image_url', defaultMessage: 'HTTPS image URL (optional)' },
  addChoice: { id: 'automation.add_choice', defaultMessage: 'Add choice' },
  create: { id: 'automation.create', defaultMessage: 'Create rule' },
  enable: { id: 'automation.enable', defaultMessage: 'Enable' },
  disable: { id: 'automation.disable', defaultMessage: 'Disable' },
  remove: { id: 'automation.remove', defaultMessage: 'Delete' },
  postText: { id: 'automation.timeline_post_text', defaultMessage: 'Timeline post text' },
  publish: { id: 'automation.publish', defaultMessage: 'Publish with these choices' },
  published: { id: 'automation.published', defaultMessage: 'Published to the timeline.' },
  error: { id: 'automation.error', defaultMessage: 'The automatic-reply rule could not be saved.' },
});

const ConversationAutomation: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const [rules, setRules] = useState<AutomationRuleJSON[]>([]);
  const [name, setName] = useState('');
  const [prompt, setPrompt] = useState('');
  const [keyword, setKeyword] = useState('');
  const [matchInText, setMatchInText] = useState(true);
  const [defaultResponse, setDefaultResponse] = useState('');
  const [defaultImage, setDefaultImage] = useState('');
  const [choices, setChoices] = useState<ChoiceDraft[]>([blankChoice(), blankChoice()]);
  const [failed, setFailed] = useState(false);
  const [postDrafts, setPostDrafts] = useState<Record<string, string>>({});
  const [publishedRuleId, setPublishedRuleId] = useState<string | null>(null);

  const loadRules = useCallback(() => {
    void api()
      .get<AutomationRuleJSON[]>('/api/v1/conversation_automation_rules')
      .then(({ data }) => setRules(data))
      .catch(() => setFailed(true));
  }, []);

  useEffect(() => loadRules(), [loadRules]);

  const updateChoice = (index: number, field: keyof ChoiceDraft, value: string) => {
    setChoices((current) =>
      current.map((choice, choiceIndex) =>
        choiceIndex === index ? { ...choice, [field]: value } : choice,
      ),
    );
  };

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setFailed(false);
    void api()
      .post<AutomationRuleJSON>('/api/v1/conversation_automation_rules', {
        name,
        prompt,
        trigger_keyword: keyword,
        match_in_text: matchInText,
        default_response_text: defaultResponse || null,
        default_image_url: defaultImage || null,
        active: true,
        choices_attributes: choices.filter((choice) => choice.label.trim() || choice.responseText.trim()).map((choice, position) => ({
          label: choice.label,
          response_text: choice.responseText,
          image_url: choice.imageUrl || null,
          position,
        })),
      })
      .then(({ data }) => {
        setRules((current) => [data, ...current]);
        setName('');
        setPrompt('');
        setKeyword('');
        setDefaultResponse('');
        setDefaultImage('');
        setChoices([blankChoice(), blankChoice()]);
      })
      .catch(() => setFailed(true));
  };

  const toggleRule = (rule: AutomationRuleJSON) => {
    void api()
      .put<AutomationRuleJSON>(`/api/v1/conversation_automation_rules/${rule.id}`, { active: !rule.active })
      .then(({ data }) => setRules((current) => current.map((item) => (item.id === data.id ? data : item))))
      .catch(() => setFailed(true));
  };

  const deleteRule = (ruleId: string) => {
    void api()
      .delete(`/api/v1/conversation_automation_rules/${ruleId}`)
      .then(() => setRules((current) => current.filter(({ id }) => id !== ruleId)))
      .catch(() => setFailed(true));
  };

  const publishRule = (rule: AutomationRuleJSON) => {
    const status = postDrafts[rule.id]?.trim();
    if (!status) return;

    setFailed(false);
    void api()
      .post('/api/v1/statuses', {
        status,
        visibility: 'public',
        automation_rule_id: rule.id,
      })
      .then(() => {
        setPublishedRuleId(rule.id);
        setPostDrafts((current) => ({ ...current, [rule.id]: '' }));
      })
      .catch(() => setFailed(true));
  };

  const valid =
    !!name.trim() &&
    !!keyword.trim() &&
    choices.length <= 10 &&
    choices.every((choice) =>
      (!choice.label.trim() && !choice.responseText.trim() && !choice.imageUrl.trim()) ||
      (!!choice.label.trim() && !!choice.responseText.trim()),
    ) &&
    (!!defaultResponse.trim() || choices.some((choice) => choice.label.trim() && choice.responseText.trim()));

  return (
    <Column bindToDocument={!multiColumn} label={intl.formatMessage(messages.title)}>
      <ColumnHeader title={intl.formatMessage(messages.title)} withBackButton />
      <div className='automation-settings'>
        <form onSubmit={handleSubmit}>
          <input value={name} onChange={(event) => setName(event.currentTarget.value)} placeholder={intl.formatMessage(messages.name)} />
          <input value={keyword} onChange={(event) => setKeyword(event.currentTarget.value.replace(/[\[\]]/g, ''))} placeholder={intl.formatMessage(messages.keyword)} />
          <label className='automation-settings__checkbox'>
            <input type='checkbox' checked={matchInText} onChange={(event) => setMatchInText(event.currentTarget.checked)} />
            <span>{intl.formatMessage(messages.matchInText)}</span>
          </label>
          <textarea value={prompt} onChange={(event) => setPrompt(event.currentTarget.value)} placeholder={intl.formatMessage(messages.prompt)} rows={2} />
          <textarea value={defaultResponse} onChange={(event) => setDefaultResponse(event.currentTarget.value)} placeholder={intl.formatMessage(messages.defaultResponse)} rows={2} />
          <input value={defaultImage} onChange={(event) => setDefaultImage(event.currentTarget.value)} placeholder={intl.formatMessage(messages.defaultImage)} type='url' />
          <p className='automation-settings__hint'>{intl.formatMessage(messages.randomHint)}</p>
          {choices.map((choice, index) => (
            <div className='automation-settings__choice' key={index}>
              <input value={choice.label} onChange={(event) => updateChoice(index, 'label', event.currentTarget.value)} placeholder={intl.formatMessage(messages.choice)} />
              <textarea value={choice.responseText} onChange={(event) => updateChoice(index, 'responseText', event.currentTarget.value)} placeholder={intl.formatMessage(messages.response)} rows={2} />
              <input value={choice.imageUrl} onChange={(event) => updateChoice(index, 'imageUrl', event.currentTarget.value)} placeholder={intl.formatMessage(messages.image)} type='url' />
            </div>
          ))}
          <button
            type='button'
            disabled={choices.length >= 10}
            onClick={() =>
              setChoices((current) => [...current, blankChoice()])
            }
          >
            {intl.formatMessage(messages.addChoice)}
          </button>
          <button type='submit' disabled={!valid}>{intl.formatMessage(messages.create)}</button>
          {failed && <p role='alert'>{intl.formatMessage(messages.error)}</p>}
        </form>

        <div className='automation-settings__rules'>
          {rules.map((rule) => (
            <article key={rule.id}>
              <strong>{rule.name}</strong>
              <small>[{rule.trigger_keyword}] {rule.match_in_text ? intl.formatMessage(messages.matchInText) : ''}</small>
              <p>{rule.prompt}</p>
              <div className='automation-settings__preview'>
                {rule.choices.map((choice) => (
                  <div key={choice.id}>
                    {choice.image_url && (
                      <img src={choice.image_url} alt='' loading='lazy' referrerPolicy='no-referrer' />
                    )}
                    <span>
                      <b>{choice.label}</b>
                      <small>{choice.response_text}</small>
                    </span>
                  </div>
                ))}
              </div>
              <div className='automation-settings__publish'>
                <textarea
                  value={postDrafts[rule.id] ?? ''}
                  onChange={(event) =>
                    setPostDrafts((current) => ({
                      ...current,
                      [rule.id]: event.currentTarget.value,
                    }))
                  }
                  placeholder={intl.formatMessage(messages.postText)}
                  rows={2}
                />
                <button
                  type='button'
                  disabled={!rule.active || rule.choices.length === 0 || !postDrafts[rule.id]?.trim()}
                  onClick={() => publishRule(rule)}
                >
                  {intl.formatMessage(messages.publish)}
                </button>
                {publishedRuleId === rule.id && (
                  <small>{intl.formatMessage(messages.published)}</small>
                )}
              </div>
              <div>
                <button type='button' onClick={() => toggleRule(rule)}>{intl.formatMessage(rule.active ? messages.disable : messages.enable)}</button>
                <button type='button' onClick={() => deleteRule(rule.id)}>{intl.formatMessage(messages.remove)}</button>
              </div>
            </article>
          ))}
        </div>
      </div>
      <Helmet><title>{intl.formatMessage(messages.title)}</title><meta name='robots' content='noindex' /></Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default ConversationAutomation;
