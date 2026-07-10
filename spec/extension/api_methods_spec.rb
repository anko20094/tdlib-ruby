require 'spec_helper'
require 'tdlib-ruby'

module ApiMethodsSpec
  module Types
    include Dry.Types()
  end

  # Mirrors how TD::Types::Message behaves for access patterns: a Dry::Struct
  # raises Dry::Struct::MissingAttributeError on string-key [] and has no #dig.
  class TypedMessage < Dry::Struct
    attribute :id, Types::Integer
    attribute :chat_id, Types::Integer
    attribute :media_album_id, Types::Integer
  end

  class Harness
    include TD::Extension::ApiMethods

    def initialize(client = nil, auth_ready: true)
      @client = client
      @auth_ready = auth_ready
    end
  end

  # Stand-ins for the 1.8.65 ChatJoinResult union. The pinned tdlib-schema (1.8.64) has no such
  # constants, and join_outcome classifies purely on the class name — so these reproduce the exact
  # dispatch the gem will see once the schema is regenerated, without depending on it.
  module ChatJoinResult
    Success = Struct.new(:chat_id, keyword_init: true)
    RequestSent = Struct.new(:dummy, keyword_init: true)
    GuardBotApprovalRequired = Struct.new(:bot_user_id, :query_id, keyword_init: true)
    Declined = Struct.new(:dummy, keyword_init: true)
  end
end

describe TD::Extension::ApiMethods do
  let(:client) { double('TD::Client') }
  let(:harness) { ApiMethodsSpec::Harness.new(client) }

  def typed(id, chat_id, album_id)
    ApiMethodsSpec::TypedMessage.new(id: id, chat_id: chat_id, media_album_id: album_id)
  end

  def hash_msg(id, chat_id, album_id)
    { 'id' => id, 'chat_id' => chat_id, 'media_album_id' => album_id }
  end

  describe '#group_media_groups' do
    it 'groups album parts and keeps singles as-is for raw-hash messages' do
      messages = [hash_msg(3, 1, 777), hash_msg(2, 1, 0), hash_msg(1, 1, 777)]

      expect(harness.group_media_groups(messages))
        .to eq([[hash_msg(1, 1, 777), hash_msg(3, 1, 777)], hash_msg(2, 1, 0)])
    end

    it 'groups album parts for typed structs without raising' do
      messages = [typed(3, 1, 777), typed(2, 1, 0), typed(1, 1, 777)]

      expect(harness.group_media_groups(messages))
        .to eq([[typed(1, 1, 777), typed(3, 1, 777)], typed(2, 1, 0)])
    end

    it 'returns [] for non-array input' do
      expect(harness.group_media_groups(nil)).to eq([])
    end
  end

  describe '#sort_by_id' do
    it 'sorts grouped entries by id for both shapes' do
      expect(harness.sort_by_id([[hash_msg(2, 1, 7), hash_msg(1, 1, 7)]]))
        .to eq([[hash_msg(1, 1, 7), hash_msg(2, 1, 7)]])
      expect(harness.sort_by_id([[typed(2, 1, 7), typed(1, 1, 7)]]))
        .to eq([[typed(1, 1, 7), typed(2, 1, 7)]])
    end
  end

  describe '#channel_messages' do
    it 'normalizes typed messages into string-keyed hashes' do
      res = double('Messages', messages: [typed(2, 10, 0), typed(1, 10, 777)])
      future = double('Future', value!: res)
      allow(client).to receive(:get_chat_history).and_return(future)

      expect(harness.channel_messages(10))
        .to eq([hash_msg(2, 10, 0), hash_msg(1, 10, 777)])
    end

    it 'passes raw force-fed hashes through unchanged' do
      res = { 'messages' => [hash_msg(1, 10, 0)] }
      future = double('Future', value!: res)
      allow(client).to receive(:get_chat_history).and_return(future)

      expect(harness.channel_messages(10)).to eq([hash_msg(1, 10, 0)])
    end
  end

  describe '#subscribe_to_link' do
    let(:chat) { { 'id' => -100_123, 'title' => 'Channel', 'type' => { '@type' => 'chatTypeSupergroup' } } }

    def future(value)
      double('Future', value!: value)
    end

    def td_error(message)
      TD::Error.new(TD::Types::Error.new(code: 400, message: message))
    end

    def joined(id: -100_123, title: 'Channel', type: { '@type' => 'chatTypeSupergroup' })
      { 'outcome' => 'joined', 'id' => id, 'title' => title, 'type' => type }
    end

    # 1.8.64 core: join_chat → Ok, join_chat_by_invite_link → Chat. Neither is a ChatJoinResult,
    # so both must still classify as a plain join.
    context 'with a legacy (1.8.64) join result' do
      it 'reports joined for a bare Ok, which carries no chat identity' do
        allow(client).to receive(:join_chat).with(chat_id: -1_000_000_000_123).and_return(future(TD::Types::Ok.new))

        expect(harness.subscribe_to_link('https://t.me/c/123/45')).to eq('outcome' => 'joined')
      end

      it 'reports joined with identity when the core returns the chat itself' do
        allow(client).to receive(:check_chat_invite_link).and_return(future('chat_id' => -100_123))
        allow(client).to receive(:join_chat_by_invite_link).and_return(future(chat))

        expect(harness.subscribe_to_link('https://t.me/+AbCdEf123')).to eq(joined)
      end
    end

    context 'with a 1.8.65 ChatJoinResult union' do
      let(:success) { ApiMethodsSpec::ChatJoinResult::Success.new(chat_id: -100_123) }
      let(:request_sent) { ApiMethodsSpec::ChatJoinResult::RequestSent.new }
      let(:declined) { ApiMethodsSpec::ChatJoinResult::Declined.new }
      let(:guard) { ApiMethodsSpec::ChatJoinResult::GuardBotApprovalRequired.new(bot_user_id: 7, query_id: 99) }

      before { allow(client).to receive(:search_public_chat).with(username: 'durovchannel').and_return(future(chat)) }

      it 'resolves Success through the chat the link already gave us' do
        allow(client).to receive(:join_chat).with(chat_id: -100_123).and_return(future(success))

        expect(harness.subscribe_to_link('https://t.me/durovchannel')).to eq(joined)
      end

      it 'resolves Success via get_chat when only the union carries the chat_id' do
        allow(client).to receive(:join_chat).with(chat_id: -1_000_000_000_123).and_return(future(success))
        allow(client).to receive(:get_chat).with(chat_id: -1_000_000_000_123).and_return(future(chat))

        expect(harness.subscribe_to_link('https://t.me/c/123/45')).to eq(joined)
      end

      # DNA-1208 mirror: the join already succeeded server-side; a flood wait on the follow-up
      # get_chat must not downgrade it to a failure.
      it 'keeps a Success joined when get_chat floods out, degrading to the id alone' do
        allow(client).to receive(:join_chat).with(chat_id: -1_000_000_000_123).and_return(future(success))
        allow(client).to receive(:get_chat).and_raise(td_error('Too Many Requests: retry after 5'))

        expect(harness.subscribe_to_link('https://t.me/c/123/45'))
          .to eq(joined(id: -1_000_000_000_123, title: nil, type: nil))
      end

      it 'reports request_sent with the chat identity for a join-request channel' do
        allow(client).to receive(:join_chat).with(chat_id: -100_123).and_return(future(request_sent))

        expect(harness.subscribe_to_link('https://t.me/durovchannel'))
          .to eq('outcome' => 'request_sent', 'id' => -100_123, 'title' => 'Channel')
      end

      it 'reports guard_required with the bot to approve through' do
        allow(client).to receive(:join_chat).with(chat_id: -100_123).and_return(future(guard))

        expect(harness.subscribe_to_link('https://t.me/durovchannel'))
          .to eq('outcome' => 'guard_required', 'bot_user_id' => 7, 'query_id' => 99,
                 'id' => -100_123, 'title' => 'Channel')
      end

      # checkChatInviteLink reports chat_id 0 for an approval-gated chat you are not in yet;
      # persisting that as a source id would poison the app's chat table.
      it 'drops the chat_id 0 an approval-gated invite link reports' do
        allow(client).to receive(:check_chat_invite_link).and_return(future('chat_id' => 0, 'title' => 'Secret'))
        allow(client).to receive(:join_chat_by_invite_link).and_return(future(guard))

        expect(harness.subscribe_to_link('https://t.me/+AbCdEf123'))
          .to eq('outcome' => 'guard_required', 'bot_user_id' => 7, 'query_id' => 99, 'title' => 'Secret')
      end

      it 'reports declined without inventing an identity' do
        allow(client).to receive(:join_chat).with(chat_id: -100_123).and_return(future(declined))

        expect(harness.subscribe_to_link('https://t.me/durovchannel')).to eq('outcome' => 'declined')
      end
    end

    # Only join_chat_by_invite_link raises this — rejoining a public chat via join_chat is a plain Ok.
    context 'when already a participant' do
      before do
        allow(client).to receive(:search_public_chat).and_raise(td_error('USERNAME_INVALID'))
        allow(client).to receive(:check_chat_invite_link).and_return(future('chat_id' => -100_123))
        allow(client).to receive(:join_chat_by_invite_link).and_raise(td_error('USER_ALREADY_PARTICIPANT'))
      end

      it 'wraps the resolved chat into the joined outcome instead of raising' do
        allow(client).to receive(:get_chat).with(chat_id: -100_123).and_return(future(chat))

        expect(harness.subscribe_to_link('https://t.me/+AbCdEf123')).to eq(joined)
      end
    end

    context 'resolving a bare channel name' do
      it 'returns nil for a username nobody occupies' do
        allow(client).to receive(:search_public_chat).and_raise(td_error('USERNAME_NOT_OCCUPIED'))

        expect(harness.subscribe_to_link('@ghostchannel')).to be_nil
      end

      # A bare `rescue TD::Error → nil` here used to tombstone a live source on a flood wait.
      it 're-raises a flood wait so the caller can classify and retry it' do
        allow(client).to receive(:search_public_chat).and_raise(td_error('Too Many Requests: retry after 5'))

        expect { harness.subscribe_to_link('@busychannel') }.to raise_error(TD::Error, /Too Many Requests/)
      end
    end
  end

  describe '#forward_messages_to_bot' do
    let(:message_future) { double('Future', value!: typed(1, 10, 0)) }

    before { allow(client).to receive(:get_message).and_return(message_future) }

    it 'normalizes the typed Messages result so callers can read result[messages]' do
      result = TD::Types::Messages.new(total_count: 0, messages: [])
      future = double('Future', value!: result)
      allow(client).to receive(:forward_messages).and_return(future)

      expect(harness.forward_messages_to_bot(555, 10, [1]))
        .to eq('@type' => 'messages', 'total_count' => 0, 'messages' => [])
    end

    it 'preloads every source message into the session before forwarding' do
      result = TD::Types::Messages.new(total_count: 0, messages: [])
      allow(client).to receive(:forward_messages).and_return(double('Future', value!: result))

      harness.forward_messages_to_bot(555, 10, [1, 2])

      expect(client).to have_received(:get_message).with(chat_id: 10, message_id: 1)
      expect(client).to have_received(:get_message).with(chat_id: 10, message_id: 2)
    end
  end

  describe '#start_chat_with_bot' do
    let(:captured) { {} }

    before do
      allow(client).to receive(:send_message) do |**kwargs|
        captured[:content] = kwargs[:input_message_content]
        double('Future', value!: TD::Types::Ok.new)
      end
    end

    it 'sends a bare /start when no payload is given' do
      harness.start_chat_with_bot(123)

      expect(captured[:content].dig('text', 'text')).to eq('/start')
    end

    it 'sends /start <payload> outside production' do
      harness.start_chat_with_bot(123, 'userbot-foreign-7')

      expect(captured[:content].dig('text', 'text')).to eq('/start userbot-foreign-7')
    end

    it 'drops the payload in production' do
      allow(harness).to receive(:production_environment?).and_return(true)

      harness.start_chat_with_bot(123, 'userbot-foreign-7')

      expect(captured[:content].dig('text', 'text')).to eq('/start')
    end
  end

  describe '#get_messages' do
    it 'normalizes each fetched message into a string-keyed hash' do
      allow(client).to receive(:get_message).with(chat_id: 10, message_id: 1)
        .and_return(double('Future', value!: typed(1, 10, 0)))
      allow(client).to receive(:get_message).with(chat_id: 10, message_id: 2)
        .and_return(double('Future', value!: typed(2, 10, 777)))

      expect(harness.get_messages(10, [1, 2])).to eq([hash_msg(1, 10, 0), hash_msg(2, 10, 777)])
    end

    it 'skips ids whose getMessage raises and keeps the rest' do
      allow(client).to receive(:get_message).with(chat_id: 10, message_id: 1)
        .and_raise(TD::Error.new(TD::Types::Error.new(code: 5, message: 'Message not found')))
      allow(client).to receive(:get_message).with(chat_id: 10, message_id: 2)
        .and_return(double('Future', value!: typed(2, 10, 0)))

      expect { expect(harness.get_messages(10, [1, 2])).to eq([hash_msg(2, 10, 0)]) }
        .to output(/get_message failed for 10\/1/).to_stdout
    end

    it 'returns [] when the client is not logged in' do
      logged_out = ApiMethodsSpec::Harness.new(client, auth_ready: false)

      expect { expect(logged_out.get_messages(10, [1])).to eq([]) }.to output(/not logged in/).to_stdout
    end
  end

  describe '#get_media_group' do
    def slice_future(*messages)
      double('Future', value!: { 'messages' => messages })
    end

    it 'returns the normalized anchor alone for a non-album message without a request' do
      expect(harness.get_media_group(10, typed(1, 10, 0))).to eq([hash_msg(1, 10, 0)])
    end

    it 'collects the whole album from one enclosed history slice' do
      allow(client).to receive(:get_chat_history).and_return(
        slice_future(hash_msg(9, 10, 0), hash_msg(5, 10, 777), hash_msg(4, 10, 777),
                     hash_msg(3, 10, 777), hash_msg(1, 10, 0))
      )

      expect(harness.get_media_group(10, hash_msg(4, 10, 777)))
        .to eq([hash_msg(3, 10, 777), hash_msg(4, 10, 777), hash_msg(5, 10, 777)])
      expect(client).to have_received(:get_chat_history).once
    end

    it 'refetches while the history slice keeps adding parts' do
      allow(client).to receive(:get_chat_history).and_return(
        slice_future(hash_msg(4, 10, 777)),
        slice_future(hash_msg(9, 10, 0), hash_msg(5, 10, 777), hash_msg(4, 10, 777), hash_msg(1, 10, 0))
      )

      expect(harness.get_media_group(10, hash_msg(4, 10, 777)))
        .to eq([hash_msg(4, 10, 777), hash_msg(5, 10, 777)])
      expect(client).to have_received(:get_chat_history).twice
    end

    it 'raises TD::Error when the history fetch times out' do
      allow(client).to receive(:get_chat_history).and_return(double('Future', value!: nil))

      expect { harness.get_media_group(10, hash_msg(4, 10, 777)) }.to raise_error(TD::Error, /timed out/)
    end
  end

  describe 'auth guards' do
    let(:harness) { ApiMethodsSpec::Harness.new(client, auth_ready: false) }

    it 'returns [] from channel_messages when not authorized' do
      result = nil
      expect { result = harness.channel_messages(10) }.to output(/not logged in/).to_stdout
      expect(result).to eq([])
    end

    it 'returns nil from subscribe_to_link when not authorized' do
      result = nil
      expect { result = harness.subscribe_to_link('https://t.me/c/1/2') }.to output(/not logged in/).to_stdout
      expect(result).to be_nil
    end
  end

  describe '#resolve_chat_id (private)' do
    def td_error(message)
      TD::Error.new(TD::Types::Error.new(code: 400, message: message))
    end

    it 'degrades to nil only for unknown usernames' do
      allow(client).to receive(:search_public_chat).and_raise(td_error('USERNAME_INVALID'))

      expect(harness.__send__(:resolve_chat_id, '@ghost')).to be_nil
    end

    it 're-raises other TD errors so flood waits stay visible to callers' do
      allow(client).to receive(:search_public_chat).and_raise(td_error('Too Many Requests: retry after 5'))

      expect { harness.__send__(:resolve_chat_id, '@busy') }.to raise_error(TD::Error, /Too Many Requests/)
    end
  end
end
