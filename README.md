# tdlib-ruby

[![Maintainability](https://api.codeclimate.com/v1/badges/9362ca2682b7edbae205/maintainability)](https://codeclimate.com/github/centosadmin/tdlib-ruby/maintainability) [![Build Status](https://travis-ci.org/southbridgeio/tdlib-ruby.svg?branch=master)](https://travis-ci.org/centosadmin/tdlib-ruby)

## Description

Ruby bindings and client for TDLib (Telegram database library).

## Requirements

* Ruby 2.4+
* Compiled [tdlib](https://github.com/tdlib/td)

We have precompiled versions for CentOS 6 & 7 in our repositories:

http://rpms.southbridge.ru/rhel7/stable/x86_64/

http://rpms.southbridge.ru/rhel6/stable/x86_64/

And also SRPMS:

http://rpms.southbridge.ru/rhel7/stable/SRPMS/

http://rpms.southbridge.ru/rhel6/stable/SRPMS/

## Compatibility table

| Gem Version   |   | tdlib version |
|:-------------:|:-:| :-----------: |
| 1.x           | → | 1.0 - 1.2     |
| 2.0           | → | 1.3           |
| 2.1           | → | 1.5           |
| 2.2           | → | 1.6           |

IMPORTANT: From version 3.0 types schema is extracted to a separate gem: https://github.com/southbridgeio/tdlib-schema
If you want to support specific tdlib version, just set a dependency in your Gemfile:

```ruby
gem 'tdlib-schema', '~> 1.7.0'
```

## Install

Add to your gemfile:

```ruby
gem 'tdlib-ruby'
```
and run *bundle install*.


Or just run *gem install tdlib-ruby*

## Basic authentication example

```ruby
require 'tdlib-ruby'

TD.configure do |config|
  config.lib_path = 'path_to_dir_containing_tdlibjson'

  config.client.api_id = your_api_id
  config.client.api_hash = 'your_api_hash'
end

TD::Api.set_log_verbosity_level(1)

client = TD::Client.new

begin
  state = nil

  client.on(TD::Types::Update::AuthorizationState) do |update|
    state = case update.authorization_state
            when TD::Types::AuthorizationState::WaitPhoneNumber
              :wait_phone_number
            when TD::Types::AuthorizationState::WaitCode
              :wait_code
            when TD::Types::AuthorizationState::WaitPassword
              :wait_password
            when TD::Types::AuthorizationState::Ready
              :ready
            else
              nil
            end
  end
  
  client.connect

  loop do
    case state
    when :wait_phone_number
      puts 'Please, enter your phone number:'
      phone = STDIN.gets.strip
      client.set_authentication_phone_number(phone_number: phone, settings: nil).wait
    when :wait_code
      puts 'Please, enter code from SMS:'
      code = STDIN.gets.strip
      client.check_authentication_code(code: code).wait
    when :wait_password
      puts 'Please, enter 2FA password:'
      password = STDIN.gets.strip
      client.check_authentication_password(password: password).wait
    when :ready
      client.get_me.then { |user| @me = user }.rescue { |err| puts "error: #{err}" }.wait
      break
    end
    sleep 0.1
  end

ensure
  client.dispose
end

p @me
```

Client methods are being executed asynchronously and return Concurrent::Promises::Future (see: https://github.com/ruby-concurrency/concurrent-ruby/blob/master/docs-source/promises.in.md).

## Configuration

```ruby
TD.configure do |config|
  config.lib_path = 'path/to/dir_containing_libtdjson' # libtdjson will be searched in this directory (*.so, *.dylib, *.dll are valid extensions). For Rails projects, if not set, will be considered as project_root_path/vendor. If not set and file doesn't exist in vendor, it will try to find lib by ldconfig (only on Linux).
  config.encryption_key = 'your_encryption_key' # it's not required

  config.client.api_id = 12345
  config.client.api_hash = 'your_api_hash'
  config.client.use_test_dc = true # default: false
  config.client.database_directory = 'path/to/db/dir' # default: "#{Dir.home}/.tdlib-ruby/db"
  config.client.files_directory = 'path/to/files/dir' # default: "#{Dir.home}/.tdlib-ruby/files"
  config.client.use_file_database = true # default: true
  config.client.use_chat_info_database = true # default: true
  config.client.use_secret_chats = true # default: true
  config.client.use_message_database = true # default: true
  config.client.system_language_code = 'ru' # default: 'en'
  config.client.device_model = 'Some device model' # default: 'Ruby TD client'
  config.client.system_version = '42' # default: 'Unknown'
  config.client.application_version = '1.0' # default: '1.0'
  config.client.enable_storage_optimizer = true # default: true
  config.client.ignore_file_names = true # default: false
end
```

## Advanced

You can get rid of large tdlib log with

```ruby
TD::Api.set_log_verbosity_level(1)
```

You can also set log file path:

```ruby
TD::Api.set_log_file_path('path/to/log_file')
```

Additional options can be passed to client:

```ruby
TD::Client.new(database_directory: 'will override value from config',
               files_directory: 'will override value from config')
```

If the tdlib schema changes, then `./bin/parse` can be run to
synchronize the Ruby types with the new schema. Please look through
`lib/tdlib/client_methods.rb` carefully, especially the set_password
method!


## License

[MIT](https://github.com/centosadmin/tdlib-ruby/blob/master/LICENSE.txt)

## Authors

The gem is designed by [Southbridge](https://southbridge.io)

Typeization made by [Yuri Mikhaylov](https://github.com/yurijmi) 


# EXTENSION DOCUMENTATION

# `api_methods.rb`

## subscribe_to_link(raw_link)
- Signature: `subscribe_to_link(raw_link)`
- Params:
    - `raw_link` — String-like link to subscribe to.
- Returns:
    - Result of the successful underlying join call or `nil` on failure.
- API calls (delegates to helpers):
    - `subscribe_by_message_link` → `@client.join_chat`
    - `subscribe_by_username_link` → `@client.search_public_chat`, `@client.join_chat`
    - `subscribe_by_invite_link` → `@client.check_chat_invite_link`, `@client.join_chat_by_invite_link`
- Notes:
    - Requires authorization (`logged_in?`). Rescues `StandardError` and returns `nil` on error.

## chat_ids(limit = 1000)
- Signature: `chat_ids(limit = 1000)`
- Params:
    - `limit` — Integer maximum number of chats to request (default: 1000).
- Returns:
    - Array of chat ids or `nil` on error. Returns empty array when not logged in.
- API calls:
    - `@client.get_chats(chat_list: { '@type' => 'chatListMain' }, limit:)`
- Notes:
    - Rescues `ArgumentError` and `TypeError` and returns `nil` (logs error).

## channel_messages(chat_id, from_message_id = 0, limit = 99, offset = 0)
- Signature: `channel_messages(chat_id, from_message_id = 0, limit = 99, offset = 0)`
- Params:
    - `chat_id` — Integer chat identifier.
    - `from_message_id` — Integer start message id (default: 0).
    - `limit` — Integer number of messages to fetch (default: 99).
    - `offset` — Integer offset in history (default: 0).
- Returns:
    - Array of message hashes (or empty array on error). Returns empty array when not logged in.
- API calls:
    - `@client.get_chat_history(chat_id:, from_message_id:, limit:, offset:, only_local: false)`
- Notes:
    - Logs and returns `[]` on errors.

## read_messages(chat_id, message_ids)
- Signature: `read_messages(chat_id, message_ids)`
- Params:
    - `chat_id` — Integer chat identifier.
    - `message_ids` — Array of Integer message ids (or single id depending on usage).
- Returns:
    - Result of `view_messages` API call (or raises if underlying call errors).
- API calls:
    - `@client.open_chat(chat_id:)`
    - `@client.view_messages(chat_id:, message_ids:, force_read: true, source: nil)`
- Notes:
    - No explicit rescue in method.

## start_chat_with_bot(bot)
- Signature: `start_chat_with_bot(bot)`
- Params:
    - `bot` — Integer chat id or bot username.
- Returns:
    - Result of `@client.send_message` or `nil` on error. Returns nothing when not logged in or chat not found.
- API calls:
    - `resolve_chat_id` (which may call `@client.search_public_chat`)
    - `@client.send_message(...)` with `inputMessageText` containing `/start`
- Notes:
    - Catches `ArgumentError` and `TypeError`, logs and returns `nil`.

## forward_messages_to_bot(bot, from_chat_id, message_ids)
- Signature: `forward_messages_to_bot(bot, from_chat_id, message_ids)`
- Params:
    - `bot` — Integer chat id or bot username.
    - `from_chat_id` — Integer source chat id.
    - `message_ids` — Array of Integer message ids to forward.
- Returns:
    - Result of `@client.forward_messages` or `nil` on error. Returns nothing if not logged in or bot chat not found.
- API calls:
    - `resolve_chat_id` (may call `@client.search_public_chat`)
    - `@client.forward_messages(...)`
- Notes:
    - Catches `ArgumentError` and `TypeError`, logs and returns `nil`.

## group_media_groups(messages)
- Signature: `group_media_groups(messages)`
- Params:
    - `messages` — Array of message hashes.
- Returns:
    - Array where each media album is grouped as an Array of messages; single messages kept as-is. Returns `[]` if input is not an Array.
- API calls:
    - None (pure local processing).
- Notes:
    - Groups by `media_album_id` or `media.album_id` and sorts grouped albums by message id.

## fetch_interaction_info(message)
- Signature: `fetch_interaction_info(message)`
- Params:
    - `message` — Hash representing a message.
- Returns:
    - The `interaction_info` structure or `nil`.
- API calls:
    - None (uses `HashHelper` extraction).

## fetch_post_comments(chat_id, message_id, limit = 100)
- Signature: `fetch_post_comments(chat_id, message_id, limit = 100)`
- Params:
    - `chat_id` — Integer chat id containing the post.
    - `message_id` — Integer id of the post (used as `message_thread_id`).
    - `limit` — Integer maximum comments to fetch (default: 100).
- Returns:
    - Array of comment messages (empty array on error). Returns `[]` when not logged in.
- API calls:
    - `@client.get_message_thread_history(chat_id:, message_id:, from_message_id: 0, offset: 0, limit:)`
- Notes:
    - Filters out the original post from results (if present).
    - Catches `TD::Error` and generic `StandardError`, logs and returns `[]`.

---

# TD::Extension::CustomUpdateHandler
The module implements an update routing mechanism (Updates) from TDLib.


- def handlers super.merge({new_updates}) end,
  - to preserve base logic (new_message etc.)


- Basic handler methods:
    - `new_message` — handles TD::Types::Update::ChatReadInbox (performs basic actions and calls `message_sending`)
    - `message_deletion` — handles TD::Types::Update::DeleteMessages
    - `message_editing` — handles TD::Types::Update::MessageEdited
---
# TD::Extension::MediaLoader

The module is designed for managing media files: downloading incoming files from Telegram to the local disk and preliminary uploading of local files to Telegram servers.

## ⚡️ File Handling Methods

The module provides synchronous methods for file transfer and status monitoring:

| Method | Parameters | Description |
| :--- | :--- | :--- |
| `download_file` | `file_id`, `dest_dir` | Downloads a file by ID, waits for completion, and moves it from the TDLib cache to the target folder `dest_dir`. Returns the local path to the file. |
| `preliminary_upload_file` | `path`, `type` | Initiates the upload of a local file to the Telegram server (in preparation for sending). Returns the internal file ID. |
| `wait_for_upload` | `file_id`, `timeout` | Blocks execution in a loop, waiting for confirmation of successful file upload to the server (`is_uploading_completed`). |

### 📌 Implementation Details

* **`download_file`**: Works only if information about the file is already cached by TDLib (e.g., after receiving a message object).
* **`preliminary_upload_file`**: The `type` argument determines the file type for Telegram. Supported types:
    * `:photo`
    * `:video`
    * `:video_note` (video note/circle)
    * `:voice_note` (voice note)
    * Any other value: treated as `Document`.
* **`wait_for_upload`**: Checks success via several criteria: the `is_uploading_completed` flag, presence of `remote.unique_id`, or comparison `uploaded_size >= expected_size`.

---

---

# TD::TelegramClient
# Requires entering a code from a message during the first authorization

This is a base wrapper class over `TD::Client`. It unifies all extension modules, manages the connection lifecycle, authorization, and the main event processing loop.

**Architectural pattern:** This class is designed for **inheritance**. To create your own bot or client, you must create a new class that inherits from `TD::TelegramClient`.

## 🧩 Connected Modules

The class automatically integrates functionality from the following extensions:

* `TD::Extension::ApiMethods` — API interaction methods (sending messages, search, etc.).
* `TD::Extension::MediaLoader` — file downloading and uploading.
* `TD::Extension::Connection` — connection and authorization logic.
* `TD::Extension::CustomUpdateHandler` (**Prepend**) — interception and routing of incoming updates (Updates).

## ⚙️ Initialization and Parameters

```ruby
client = MyClient.new(phone: '380...', media_directory: './media')


TD.configure do |c|
  c.lib_path = 'path to tdlib library'
  c.client.api_id = 'api_id my.telegram.org'
  c.client.api_hash =  'api_hash my.telegram.org'
  c.client.database_directory = './tdlib_data/files'
  c.client.files_directory = './tdlib_data/database'
  c.client.use_test_dc = false
  c.client.use_file_database = true
  c.client.use_chat_info_database = true
  c.client.use_message_database = true
end
```

