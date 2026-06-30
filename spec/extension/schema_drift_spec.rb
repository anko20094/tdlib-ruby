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

  describe 'patched struct construction' do
    it 'builds MessageReplyTo::Message when the core omits poll_option_id' do
      message = TD::Types::MessageReplyTo::Message.new(
        'chat_id' => 1, 'message_id' => 2, 'checklist_task_id' => 0, 'origin_send_date' => 0
      )

      expect(message.poll_option_id).to eq('')
    end

    it 'builds ChatPermissions when the core omits can_react_to_messages' do
      permissions = TD::Types::ChatPermissions.new(
        'can_send_basic_messages' => true, 'can_send_audios' => true, 'can_send_documents' => true,
        'can_send_photos' => true, 'can_send_videos' => true, 'can_send_video_notes' => true,
        'can_send_voice_notes' => true, 'can_send_polls' => true, 'can_send_other_messages' => true,
        'can_add_link_previews' => true, 'can_edit_tag' => true, 'can_change_info' => true,
        'can_invite_users' => true, 'can_pin_messages' => true, 'can_create_topics' => true
      )

      expect(permissions.can_react_to_messages).to be(false)
    end
  end
end
