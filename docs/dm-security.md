# Direct-message access rules

Direct messages in this fork are not end-to-end encrypted. They are direct-visibility statuses stored by the server.

## Authorization matrix

| Operation | Active participant | Non-participant | Administrator outside conversation |
| --- | --- | --- | --- |
| List own conversations | Allowed | Own list only | Own list only |
| Read through participant API | Allowed | Denied with 404 | Denied with 404 |
| Send message | Allowed | Denied with 404 | Denied with 404 |
| Mark read/unread | Allowed | Denied with 404 | Denied with 404 |
| Rename or add participants | Owner only | Denied with 404 | Denied with 404 |
| Leave | Non-owner participant | Denied with 404 | Denied with 404 |
| Delete own conversation entry | Allowed | Denied with 404 | Denied with 404 |
| Read through administrator API | Not unless administrator | Denied with 403 | Allowed, read-only |

## Enforcement

- Participant endpoints resolve `AccountConversation` through `current_account`; a caller cannot substitute another account's record ID.
- Administrator endpoints require the administrator role and never create a mention, membership, or `AccountConversation` for the administrator.
- Administrator endpoints expose only direct-visibility statuses stored by this server.
- Administrator list and message-history requests append an `Admin::ActionLog` entry.
- Administrator endpoints have no create, update, send, delete, read-state, participant, or leave routes.

## Required release checks

1. Run `bundle exec rails db:migrate`.
2. Run the conversation and administrator request specs.
3. Verify participant, unrelated-user, and administrator accounts in separate browser sessions.
4. Verify that administrator reads do not alter mentions, memberships, recipients, unread state, or ActivityPub deliveries.
5. Disclose administrator access in the server privacy policy before production use.

## Timeline automatic responses

- A timeline choice never exposes its configured response text through the public status API.
- Choosing an option rechecks status visibility and creates a direct message only between the local post author and the selecting account.
- The post author cannot select their own option, and each account can execute a card only once.
- Rules are copied into an immutable per-status snapshot so later rule edits do not change published choices.
- Optional images currently use HTTPS URLs with referrer suppression. The remote image host can still observe the viewer's network address; production deployments should use uploaded media or a trusted image proxy.

## Bracketed DM triggers

- A rule can require an exact message such as `[배송조회]` or explicitly allow the token inside a longer message such as `안녕하세요 [배송조회] 부탁해요`.
- Trigger matching is performed only for messages submitted through the authenticated conversation send endpoints; automatic responses are not scanned again.
- Rules with choices expose a visually separate choice card. Rules without choices send their configured default response immediately.
- A choice endpoint rechecks the sender's latest message, conversation membership, active rule, and functional local rule owner before sending.
- Duplicate choice labels are exposed as one button. The server ignores the requested record as an exact response and selects a variant from the normalized label group.
- Duplicate trigger keywords owned by the same account are reduced to one stable random rule per triggering message, preventing multiple bot replies and result changes after refresh.
- The execution log stores the actual response variant that was sent.
