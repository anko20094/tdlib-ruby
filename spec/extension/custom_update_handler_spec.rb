require 'spec_helper'
require 'tdlib-ruby'

# Mirrors the production wiring: the module is prepended to TD::TelegramClient,
# and the app's listener subclasses it overriding #message_sending.
class DummyTelegramClient
  prepend TD::Extension::CustomUpdateHandler

  def initialize(params = {}); end
end

class DummyListener < DummyTelegramClient
  attr_reader :sent_batches

  def initialize(params = {})
    @sent_batches = []
    @sent_mutex = Mutex.new

    super
  end

  def message_sending(messages)
    @sent_mutex.synchronize { @sent_batches << messages }
  end
end

describe TD::Extension::CustomUpdateHandler do
  let(:handler) { DummyListener.new }

  def message(id, chat_id, album_id)
    { 'id' => id, 'chat_id' => chat_id, 'media_album_id' => album_id }
  end

  def wait_until(timeout: 2.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    sleep 0.01 while !yield && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
  end

  def wait_for_batches(count)
    wait_until { handler.sent_batches.size >= count }
  end

  describe 'configuration' do
    it 'defaults media_group_debounce to 3.0 seconds' do
      expect(TD.config.media_group_debounce).to eq(3.0)
    end

    it 'defaults media_group_max_hold to 10.0 seconds' do
      expect(TD.config.media_group_max_hold).to eq(10.0)
    end

    it 'reads the debounce window from TD.config' do
      expect(handler.media_group_debounce).to eq(TD.config.media_group_debounce)
      expect(handler.media_group_max_hold).to eq(TD.config.media_group_max_hold)
    end
  end

  describe 'buffering' do
    before do
      TD.config.media_group_debounce = 0.05
      TD.config.media_group_max_hold = 0.5
    end

    after do
      TD.config.media_group_debounce = 3.0
      TD.config.media_group_max_hold = 10.0
    end

    describe '#enqueue_media_group' do
      it 'flushes buffered album parts in one batch after the debounce window' do
        handler.enqueue_media_group(10, 777, message(1, 10, 777))
        handler.enqueue_media_group(10, 777, message(2, 10, 777))

        wait_for_batches(1)

        expect(handler.sent_batches).to eq([[message(1, 10, 777), message(2, 10, 777)]])
      end

      it 'does not flush before the debounce window elapses' do
        TD.config.media_group_debounce = 0.3

        handler.enqueue_media_group(10, 777, message(1, 10, 777))
        sleep 0.05

        expect(handler.sent_batches).to be_empty
      end

      it 'keeps albums with the same id from different chats in separate batches' do
        handler.enqueue_media_group(10, 777, message(1, 10, 777))
        handler.enqueue_media_group(20, 777, message(2, 20, 777))

        wait_for_batches(2)

        expect(handler.sent_batches).to contain_exactly([message(1, 10, 777)], [message(2, 20, 777)])
      end

      it 'keeps different albums from the same chat in separate batches' do
        handler.enqueue_media_group(10, 777, message(1, 10, 777))
        handler.enqueue_media_group(10, 888, message(2, 10, 888))

        wait_for_batches(2)

        expect(handler.sent_batches).to contain_exactly([message(1, 10, 777)], [message(2, 10, 888)])
      end

      it 'buffers a duplicate message id only once' do
        handler.enqueue_media_group(10, 777, message(1, 10, 777))
        handler.enqueue_media_group(10, 777, message(1, 10, 777))

        wait_for_batches(1)

        expect(handler.sent_batches).to eq([[message(1, 10, 777)]])
      end

      it 'flushes by the hard cap when parts keep arriving within the debounce window' do
        TD.config.media_group_debounce = 0.08
        TD.config.media_group_max_hold = 0.2

        # Parts stream every 0.03s, so the debounce timer alone would reset forever;
        # the deadline must force intermediate flushes without losing or duplicating parts.
        12.times do |i|
          handler.enqueue_media_group(10, 777, message(i, 10, 777))
          sleep 0.03
        end
        wait_until { handler.sent_batches.sum(&:size) == 12 }

        expect(handler.sent_batches.size).to be >= 2
        expect(handler.sent_batches.flatten.map { |msg| msg['id'] }.sort).to eq((0..11).to_a)
      end
    end

    describe '#flush_media_group' do
      it 'does nothing for an unknown buffer key' do
        handler.flush_media_group([10, 777])

        expect(handler.sent_batches).to be_empty
      end
    end
  end
end
