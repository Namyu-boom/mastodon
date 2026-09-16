import { useState } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import type { Map as ImmutableMap, List as ImmutableList } from 'immutable';

import api from 'mastodon/api';

type ChoiceList = ImmutableList<ImmutableMap<string, string | null>>;

const messages = defineMessages({
  sent: { id: 'automation.sent_to_dm', defaultMessage: 'The response was sent to your messages.' },
  error: { id: 'automation.selection_error', defaultMessage: 'The option could not be selected.' },
});

export const StatusAutomationCard: React.FC<{
  statusId: string;
  card: ImmutableMap<string, unknown>;
}> = ({ statusId, card }) => {
  const intl = useIntl();
  const [selected, setSelected] = useState(Boolean(card.get('selected')));
  const [pending, setPending] = useState(false);
  const [failed, setFailed] = useState(false);
  const choices = card.get('choices') as ChoiceList;
  const selectable = Boolean(card.get('selectable'));

  const selectChoice = (choiceId: string) => {
    if (selected || pending) return;
    setPending(true);
    setFailed(false);
    void api()
      .post(`/api/v1/statuses/${statusId}/automation_choices/${choiceId}`)
      .then(() => setSelected(true))
      .catch(() => setFailed(true))
      .finally(() => setPending(false));
  };

  return (
    <section className='status-automation-card'>
      <strong>{card.get('prompt') as string}</strong>
      {!selected && selectable && (
        <div className='status-automation-card__choices'>
          {choices.map((choice) => (
            <button
              type='button'
              key={choice.get('id') as string}
              disabled={pending}
              onClick={() => selectChoice(choice.get('id') as string)}
            >
              {choice.get('image_url') && (
                <img
                  src={choice.get('image_url') as string}
                  alt=''
                  loading='lazy'
                  referrerPolicy='no-referrer'
                />
              )}
              <span>{choice.get('label') as string}</span>
            </button>
          ))}
        </div>
      )}
      {selected && <p>{intl.formatMessage(messages.sent)}</p>}
      {failed && <p role='alert'>{intl.formatMessage(messages.error)}</p>}
    </section>
  );
};
