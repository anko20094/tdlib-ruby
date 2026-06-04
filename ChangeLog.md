### 3.3.2 / 2026-06-05

* Remove dead extension methods with no callers: chat_ids, fetch_interaction_info,
  fetch_post_comments, get_chat_full_info, get_message, preliminary_upload_file,
  wait_for_upload
* Fix logged_in? always returning true — the auth guards in ApiMethods work again
* resolve_chat_id swallows only USERNAME_INVALID/USERNAME_NOT_OCCUPIED; other TD errors
  (flood wait, network) propagate to callers
* Drop rescue ArgumentError/TypeError blocks that never caught real TD failures and
  printed a misleading "Error forwarding messages"
* Replace remaining ActiveSupport-only blank?/present? with plain Ruby (the gem has no
  activesupport dependency)
* message_editing reads the singular message_id of Update::MessageEdited (message_ids
  raised NoMethodError); message_sending is an explicit abstract hook now
* setup_directories creates the per-instance database/files directories actually passed
  to TD::Client instead of the unused TD.config globals
* README: document the real constructor params (files_directory, not media_directory),
  the data-shape contract and the message_sending hook; drop docs of removed methods

### 3.3.1 / 2026-06-05

* Normalize extension API returns to string-keyed hashes: channel_messages,
  subscribe_to_link and forward_messages_to_bot now deep_to_hash their results,
  restoring the raw-hash contract consumers were written against
* HashHelper.deep_to_hash restores the TDLib '@type' key on every nesting level
  for typed structs (Dry::Struct#to_h silently drops it)
* group_media_groups / sort_by_id read ids via HashHelper instead of string-key
  [] / #dig, which raise on typed TD::Types::Message structs

### 3.3.0 / 2026-06-04

* Require tdlib-schema >= 1.8.64.0 (regenerated for TDLib 1.8.64) and rename
  `message_thread_id:` to `topic_id:` in send_message/forward_messages calls
* Log updates that TD::Types.wrap cannot parse before falling back to raw-hash delivery
  (unknown @type from a newer core is no longer swallowed silently)
* Surface auth-step failures: set_authentication_phone_number errors are logged and re-raised;
  check/resend code failures are logged
* Map WaitOtherDeviceConfirmation in AUTH_STATE_MAP (QR wait state no longer reported as unknown)

### 3.0.4 / 2024-09-05

* Change ffi gem version to '~> 1.15.0'

### 3.0.3 / 2024-08-29

* Remove the verification encryption key and unnecessary configurations

### 3.0.2 / 2020-06-29

* Rescue exceptions in update manager thread

### 3.0.1 / 2020-06-29

* Fix client dispose

### 3.0.0 / 2020-06-28

* Extract schema to separate gem

### 2.1.0 / 2019-10-18

* Support tdlib 1.5
* Fix TD::Client#dispose race condition and client crash

### 2.0.0 / 2019-02-08

* Generated types and client functions
* Async handlers
* Use ffi instead of fiddle
* Use Concurrent::Promises
* TD errors handling in promises
* Add use_file_database setting to config

### 1.0.0 / 2018-05-27

* Return promises from TD::Client#broadcast
* Add #fetch as alias to #broadcast_and_receive

### 0.9.4 / 2018-05-16

* Fix recursive locking in nested handlers

### 0.9.3 / 2018-05-04

* Add proxy support

### 0.9.2 / 2018-05-04

* Fix some potential deadlocks

### 0.9.1 / 2018-04-27

* Fix deadlock in Client#on_ready

### 0.9.0 / 2018-04-26

* Use Celluloid

### 0.8.0 / 2018-04-25

* Fix await methods

### 0.4.0 / 2018-04-12

* Add configurable timeout
* Fix hanging threads after timeout

### 0.3.0 / 2018-04-04

* Use Concurrent::Promise instead of timeout module
* Add integration tests

### 0.2.0 / 2018-02-16

* Improved lib path detection

* TD::Client#on_ready method

### 0.1.0 / 2018-02-01

* Initial release:

Basic featues
