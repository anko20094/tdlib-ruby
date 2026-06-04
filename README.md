# tdlib-ruby

![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/anko20094/tdlib-ruby?utm_source=oss&utm_medium=github&utm_campaign=anko20094%2Ftdlib-ruby&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews) [![Maintainability](https://api.codeclimate.com/v1/badges/9362ca2682b7edbae205/maintainability)](https://codeclimate.com/github/centosadmin/tdlib-ruby/maintainability) [![Build Status](https://travis-ci.org/southbridgeio/tdlib-ruby.svg?branch=master)](https://travis-ci.org/centosadmin/tdlib-ruby)

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

Fork-specific layer on top of `TD::Client`: a subclassable `TD::TelegramClient` plus
extension modules (`ApiMethods`, `MediaLoader`, `Connection`, `CustomUpdateHandler`).

## Data-shape contract

Every public `ApiMethods` call that returns TDLib data normalizes it with
`TD::Extension::HashHelper.deep_to_hash`: string-keyed hashes with the TDLib `'@type'`
restored on every nesting level. Consumers see the same shape whether the response was
wrapped into `TD::Types` or force-fed as a raw hash by the update-manager fallback.

# `api_methods.rb`

## subscribe_to_link(raw_link)
- Joins a chat by message link (`t.me/c/...`), username link, invite link, or bare channel name.
- Returns: normalized hash of the join result/chat, or `nil` when the link cannot be resolved.
- Errors: `TD::Error` propagates, except `USER_ALREADY_PARTICIPANT`, which self-heals by
  resolving the already-joined chat.

## channel_messages(chat_id, from_message_id = 0, limit = 99, offset = 0)
- Returns: Array of normalized message hashes (newest first); `[]` when not logged in.
- Errors: `TD::Error`/timeouts propagate — callers classify them (frozen account,
  chat not found, transient).

## read_messages(chat_id, message_ids)
- Opens the chat and marks the messages as read (`force_read: true`). Errors propagate.

## start_chat_with_bot(bot)
- Sends `/start` to a bot (chat id or username). Returns the send result, or `nil` when
  the bot username cannot be resolved. `TD::Error` propagates.

## forward_messages_to_bot(bot, from_chat_id, message_ids)
- Returns: normalized hash (read `result['messages']`), or `nil` when the bot cannot be
  resolved. `TD::Error` propagates.

## group_media_groups(messages)
- Pure local processing; accepts hashes and typed structs. Albums are grouped by
  `media_album_id` into nested arrays sorted by message id; singles stay as-is.
  Returns `[]` for non-Array input.

---

# TD::Extension::CustomUpdateHandler

Update routing + media-album buffering, `prepend`ed to `TD::TelegramClient`.

- `subscribe_channel_posts(client)` routes every `TD::Types::Update` through the
  `handlers` map. Extend in a subclass with `def handlers; super.merge(...); end`.
- Default handlers: `new_message` (`Update::ChatReadInbox`), `message_deletion`
  (`Update::DeleteMessages`), `message_editing` (`Update::MessageEdited`).
- `new_message` fetches unread messages via `channel_messages`, marks the newest as
  read, and buffers album parts per `[chat_id, media_album_id]` with a debounce window
  (`TD.config.media_group_debounce`, default 3s, env `TDLIB_ALBUM_DEBOUNCE`) capped by a
  hard hold deadline (`TD.config.media_group_max_hold`, default 10s, env
  `TDLIB_ALBUM_MAX_HOLD`); then calls `message_sending`.
- `message_sending(messages)` is an **abstract hook — override it in your subclass**.
  It receives a flat Array of normalized message hashes; album parts arrive together
  after the debounce window (nesting them into groups is the consumer's job, e.g. via
  `group_media_groups`). The gem raises `NotImplementedError` if it is not overridden.

---

# TD::Extension::MediaLoader

| Method | Parameters | Description |
| :--- | :--- | :--- |
| `download_file` | `file_id`, `dest_dir:`, `timeout:` | Downloads a file by id (works once TDLib has the file cached, e.g. after receiving its message), waits for completion and moves it from the TDLib cache into `dest_dir`. Returns the local path or `nil` on error. |

---

# TD::TelegramClient

Base wrapper over `TD::Client` designed for **inheritance**: subclass it and override
the hooks (`message_sending`, `handlers`, ...). Integrates `ApiMethods`, `MediaLoader`,
`Connection` and (prepended) `CustomUpdateHandler`.

## Initialization

```ruby
TD.configure do |c|
  c.lib_path = 'path to dir with libtdjson'
  c.client.api_id = 'api_id from my.telegram.org'
  c.client.api_hash = 'api_hash from my.telegram.org'
end

class MyClient < TD::TelegramClient
  def message_sending(messages)
    # your delivery logic; messages is an Array of string-keyed hashes
  end
end

client = MyClient.new(phone: '380...',
                      database_directory: './tdlib_data/database',
                      files_directory: './tdlib_data/files', # also used as the media dir
                      by_qr: false)                          # true => QR-code login
client.run
```

Constructor params: `phone:`, `database_directory:` (default `./tdlib_database`),
`files_directory:` (default `./tdlib_files`; exposed as `#media_directory` and used by
`MediaLoader`), `by_qr:`, and optional per-instance `api_id:`/`api_hash:` overriding the
`TD.config.client` values. Both directories are created on initialization.

Interactive auth (`Connection`) asks for the SMS/app code in the terminal (`r` resends
the code) and for the 2FA password when required.
