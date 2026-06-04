# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Fork of [southbridgeio/tdlib-ruby](https://github.com/southbridgeio/tdlib-ruby) (kept as the `upstream` remote) — Ruby bindings and async client for TDLib (Telegram Database Library) via FFI. The fork exists to serve the private **dna_bot** project (`/home/danyil/Desktop/dna_bot`), which consumes it as:

```ruby
gem 'tdlib-ruby', github: 'anko20094/tdlib-ruby', branch: 'master', tag: 'vX.Y.Z'
```

Work is tracked in YouTrack under `DNA-*` issue IDs. Ruby version: 3.3.6 (`.ruby-version`).

TDLib type classes live in a separate gem, `tdlib-schema` — if a TD type or method is missing/mismatched, the fix is usually the schema gem version, not this repo.

## Commands

```bash
bundle install

# Unit tests — the only ones runnable without compiled tdlib:
bundle exec rspec spec/tdlib_spec.rb spec/tdlib spec/extension

# Single test:
bundle exec rspec spec/extension/custom_update_handler_spec.rb:70

# Full suite: spec/integration needs compiled tdlib at ../td/build
# plus TD_API_ID / TD_API_HASH env vars — it fails without them:
bundle exec rspec

# Lint — config covers only lib/**/*; bin/, lib/tdlib-ruby.rb and lib/tdlib/api.rb are excluded:
bundle exec rubocop
```

`bin/console` — IRB with the gem loaded. `bin/build` — compiles TDLib from source in `./td` (not checked out by default).

Note: `master` carries pre-existing rubocop offenses — lint what you touch, don't drive-by-fix the rest.

## Architecture

Two layers: the upstream core and this fork's extension layer.

**Core request/response flow** (`lib/tdlib/client.rb`, `update_manager.rb`, `update_handler.rb`, `api.rb`):

- `TD::Api` — raw FFI bindings to `libtdjson` (rarely touched, excluded from rubocop).
- `TD::Client#broadcast(query)` is the async primitive: it tags the query with an `@extra` UUID, registers a disposable `UpdateHandler` matching that UUID, and returns a `Concurrent::Promises::Future`. `#fetch` is the blocking variant. The per-method API (`get_chat_history`, `join_chat`, …) comes from `TD::ClientMethods` in tdlib-schema.
- `TD::UpdateManager` runs one background thread polling `TD::Api.client_receive`; each update is wrapped via `TD::Types.wrap` and dispatched to matching handlers. **If wrapping raises (schema doesn't know the type), the rescue path force-feeds the raw Hash to handlers matched by `@extra` only** — so handler code can receive either a `TD::Types` struct or a plain Hash. That is why `HashHelper.get_unknown_structure_data` exists; update-processing code must tolerate both shapes.
- Configuration is `dry-configurable` on the `TD` module (`lib/tdlib-ruby.rb`), including fork-added `media_group_debounce` / `media_group_max_hold` (env: `TDLIB_ALBUM_DEBOUNCE` / `TDLIB_ALBUM_MAX_HOLD`).

**Fork extension layer** (`lib/tdlib/telegram_client.rb`, `lib/tdlib/extension/`):

- `TD::TelegramClient` is a base class **designed for inheritance** — dna_bot subclasses it and overrides hooks. It composes the extension modules: `ApiMethods` (high-level calls: `subscribe_to_link`, `channel_messages`, `forward_messages_to_bot`, …), `MediaLoader` (file download/upload), `Connection` (interactive auth state machine: phone / SMS code / 2FA / QR), and `CustomUpdateHandler` (**prepended** — wraps `initialize` to add the media buffer and routes updates through the `handlers` map).
- Update routing: `subscribe_channel_posts` listens to all `TD::Types::Update` and dispatches via the `handlers` hash (`ChatReadInbox` → `new_message`, etc.). Subclasses extend with `def handlers; super.merge(...); end` and override `message_sending(messages)` as the downstream delivery hook.
- Media album batching: album parts are buffered per `[chat_id, media_album_id]` key with a debounce timer plus a hard hold deadline, so an endless part stream cannot keep an album in the buffer forever (`spec/extension/custom_update_handler_spec.rb` documents the exact semantics).

Behavioral docs for the extension layer live in README.md under "EXTENSION DOCUMENTATION".

## Project conventions (dna_bot "unwritten rules")

- **Commits**: `[DNA-XXXX] Imperative summary` (YouTrack ticket), with body bullets explaining what/why when non-trivial. Infra-only commits may omit the prefix.
- **Release flow**: every shipped change bumps the patch version in `lib/tdlib/version.rb` in the same commit; after it lands on `master`, the commit is tagged `vX.Y.Z`, and dna_bot's Gemfile pin (`tag: 'vX.Y.Z'`) is updated and re-locked. A change is not delivered until tagged and re-pinned in dna_bot.
- **No ActiveSupport** — the gem must work in bare consumers; plain Ruby/stdlib only (e.g. `include?`, not `exclude?`). Runtime deps stay exactly: dry-configurable, concurrent-ruby, ffi, tdlib-schema. The gemspec pins (`ffi ~> 1.15.0`, `dry-configurable ~> 0.13`) are coordinated with dna_bot's dependency resolution — don't change them unilaterally.
- **Public API stability**: dna_bot subclasses `TD::TelegramClient` and relies on `message_sending(messages)`, the `handlers` contract, and `TD::Extension::*` method signatures. Renaming or re-signaturing these breaks the consumer even when this repo's specs stay green.
- **Unit specs must not need libtdjson**: never instantiate a real `TD::Client` in unit specs — stub it (`instance_double(TD::Client)`, stub `setup_directories`/`setup_handlers`) or mirror the production wiring with dummy classes that `prepend` the module under test. Time-dependent specs shrink the config windows in `before` / restore them in `after`, and poll with a monotonic-clock `wait_until` helper rather than asserting after a fixed sleep.
- **Tolerate both struct and Hash messages** in anything processing updates — go through `HashHelper.get_unknown_structure_data` instead of calling typed accessors directly.
- **CLI output style**: user-facing console feedback uses emoji-prefixed `puts` (`✅ / ❌ / ⚠️ / ℹ️ / ➡️ / 🔄`); keep new auth/connection messages in that style.
- **PR review**: commenting `review` on a PR triggers the Claude review workflow (`.github/workflows/claude-review.yml`).
