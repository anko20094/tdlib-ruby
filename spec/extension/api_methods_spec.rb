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

    def initialize(client = nil)
      @client = client
      @auth_ready = true
    end
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
    it 'returns a string-keyed hash with @type for a typed join result' do
      future = double('Future', value!: TD::Types::Ok.new)
      allow(client).to receive(:join_chat).with(chat_id: -1_000_000_000_123).and_return(future)

      expect(harness.subscribe_to_link('https://t.me/c/123/45')).to eq('@type' => 'ok')
    end
  end

  describe '#forward_messages_to_bot' do
    it 'normalizes the typed Messages result so callers can read result[messages]' do
      result = TD::Types::Messages.new(total_count: 0, messages: [])
      future = double('Future', value!: result)
      allow(client).to receive(:forward_messages).and_return(future)

      expect(harness.forward_messages_to_bot(555, 10, [1]))
        .to eq('@type' => 'messages', 'total_count' => 0, 'messages' => [])
    end
  end
end
