require 'spec_helper'
require 'tdlib-ruby'

describe TD::Extension::SchemaDrift do
  describe '.backfill' do
    it 'adds a missing key from the defaults' do
      result = described_class.backfill({ 'chat_id' => 1 }, 'poll_option_id' => '')
      expect(result).to eq('chat_id' => 1, 'poll_option_id' => '')
    end

    it 'keeps an already-present key untouched' do
      result = described_class.backfill({ 'poll_option_id' => 'x' }, 'poll_option_id' => '')
      expect(result['poll_option_id']).to eq('x')
    end

    it 'stringifies symbol keys before filling' do
      result = described_class.backfill({ chat_id: 1 }, 'poll_option_id' => '')
      expect(result).to eq('chat_id' => 1, 'poll_option_id' => '')
    end

    it 'returns non-hash input unchanged' do
      expect(described_class.backfill(nil, 'poll_option_id' => '')).to be_nil
    end
  end

  # The real path: TD::Types.wrap raises (and TD::UpdateManager drops the whole update) when the pinned
  # tdlib-schema expects a field the older libtdjson core omits. The backfilled .new keeps wrap succeeding.
  describe 'TD::Types.wrap' do
    context 'with a reply_to message missing poll_option_id (older core)' do
      let(:reply_to) do
        {
          '@type' => 'messageReplyToMessage', 'chat_id' => 1, 'message_id' => 2,
          'checklist_task_id' => 0, 'origin_send_date' => 0
        }
      end

      it 'wraps instead of dropping, defaulting the missing field' do
        wrapped = TD::Types.wrap(reply_to)

        expect(wrapped).to be_a(TD::Types::MessageReplyTo::Message)
        expect(wrapped.poll_option_id).to eq('')
      end
    end

    context 'when poll_option_id IS present (newer core)' do
      let(:reply_to) do
        {
          '@type' => 'messageReplyToMessage', 'chat_id' => 1, 'message_id' => 2,
          'checklist_task_id' => 0, 'origin_send_date' => 0, 'poll_option_id' => '7'
        }
      end

      it 'keeps the provided value' do
        wrapped = TD::Types.wrap(reply_to)

        expect(wrapped.poll_option_id).to eq('7')
      end
    end

    context 'with chat permissions missing can_react_to_messages (older core)' do
      let(:permissions) do
        {
          '@type' => 'chatPermissions', 'can_send_basic_messages' => true, 'can_send_audios' => false,
          'can_send_documents' => false, 'can_send_photos' => true, 'can_send_videos' => true,
          'can_send_video_notes' => false, 'can_send_voice_notes' => false, 'can_send_polls' => false,
          'can_send_other_messages' => false, 'can_add_link_previews' => false, 'can_edit_tag' => false,
          'can_change_info' => false, 'can_invite_users' => false, 'can_pin_messages' => false,
          'can_create_topics' => false
        }
      end

      it 'wraps instead of dropping, defaulting the missing field' do
        wrapped = TD::Types.wrap(permissions)

        expect(wrapped).to be_a(TD::Types::ChatPermissions)
        expect(wrapped.can_react_to_messages).to be(false)
      end
    end
  end
end
