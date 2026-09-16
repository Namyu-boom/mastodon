# Mastodon customization roadmap

This roadmap tracks the custom messaging, automation, account switching, and scheduling work for this fork.

## Product decisions

- Direct messages remain ActivityPub-compatible direct-visibility statuses internally.
- Conversation recipients are stored separately and inserted into outgoing ActivityPub addressing automatically; recipient handles are hidden from the chat body.
- Automated replies use dedicated choice buttons and automation rules, not Mastodon polls.
- Administrator access to messages is isolated behind a dedicated permission and audit log. It is not part of the regular messaging API.
- Existing scheduled-status APIs and workers are reused.

## Delivery phases

### 1. Conversation foundation

- [x] Add an authenticated conversation-message history API.
- [x] Restrict history to conversations belonging to the current account.
- [x] Add cursor pagination and request specs.
- [x] Add a `/conversations/:id` chat route and message-thread UI.
- [x] Mark conversations as read when the chat is opened.

### 2. Mention-free group messages

- [x] Add conversation creation with an explicit participant list.
- [x] Add a conversation-scoped send endpoint.
- [x] Generate ActivityPub recipients and mention tags without displaying handles in message bodies.
- [x] Add participant, leave, and group-name controls.

### 3. Choice-based automated replies

- [x] Add automation rules, choices, and execution-log tables.
- [x] Add an automation management tab with create, enable/disable, and delete controls.
- [x] Render choices as buttons inside direct-message conversations.
- [x] Detect bracketed DM triggers, optionally inside longer messages.
- [x] Send an immediate default reply when a trigger has no choices.
- [x] Collapse duplicate choice labels into one button and select a response variant server-side.
- [x] Select one stable random rule when an account defines the same bracket keyword more than once.
- [x] Snapshot rules onto timeline posts and render keyword/image choice cards.
- [x] Send the selected timeline response as a private one-to-one message.
- [x] Execute one idempotent response per rule and prevent bot loops.
- [ ] Replace external image URLs with uploaded Mastodon media attachments or an instance proxy.
- [ ] Support optional delayed responses through the job queue.

### 4. Scheduled posts

- [ ] Add date/time selection to the compose UI using the existing `scheduled_at` API field.
- [ ] Add a scheduled-post management tab using `/api/v1/scheduled_statuses`.
- [ ] Support reschedule, cancel, and publish-now actions.
- [ ] Surface publish failures and preserve account time-zone context.

### 5. Account switching

- [ ] Add server-side linked-login sessions for accounts on this server.
- [ ] Add the account switcher and per-account unread state.
- [ ] Evaluate remote-server OAuth accounts as a separate follow-up.

### 6. Administrator message access

- [ ] Confirm the legal and policy requirements before production deployment.
- [x] Add an administrator-only, read-only API and explicit UI.
- [x] Record administrator list and conversation access in the audit log.
- [x] Limit access to direct messages actually stored by this server.
- [x] Keep administrators out of conversation membership and ActivityPub recipients.
