require 'spec_helper'
require 'tdlib-ruby'

describe TD::UpdateManager do
  let(:td_client) { double('td_client') }
  let(:manager) { described_class.new(td_client) }

  def wait_until(timeout: 2.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    sleep 0.01 while !yield && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
  end

  describe '#handle_update' do
    context 'when the update @type is unknown to the schema' do
      let(:raw_update) { { '@type' => 'updateUnknownToSchema', '@extra' => 'req-1', 'value' => 1 } }

      before do
        allow(TD::Api).to receive(:client_receive).and_return(raw_update)
      end

      it 'logs the unwrappable update instead of swallowing it' do
        expect { manager.__send__(:handle_update) }
          .to output(/updateUnknownToSchema.*req-1|req-1.*updateUnknownToSchema/m).to_stderr
      end

      it 'still force-feeds the raw hash to the handler matching @extra' do
        received = []
        manager.add_handler(TD::UpdateHandler.new(TD::Types::Base, 'req-1', disposable: true) { |u| received << u })

        expect { manager.__send__(:handle_update) }.to output.to_stderr
        wait_until { received.any? }

        expect(received.size).to eq(1)
        expect(received.first).to include('value' => 1)
      end
    end

    context 'when the update is known to the schema' do
      let(:raw_update) { { '@type' => 'error', 'code' => 404, 'message' => 'Not Found' } }

      before do
        allow(TD::Api).to receive(:client_receive).and_return(raw_update)
      end

      it 'wraps and delivers it without logging anything' do
        received = []
        manager.add_handler(TD::UpdateHandler.new(TD::Types::Error, nil, disposable: true) { |u| received << u })

        expect { manager.__send__(:handle_update) }.not_to output.to_stderr
        wait_until { received.any? }

        expect(received.size).to eq(1)
        expect(received.first).to be_a(TD::Types::Error)
      end
    end

    context 'when the callback raises after a successful wrap' do
      let(:raw_update) { { '@type' => 'error', '@extra' => 'req-2', 'code' => 500, 'message' => 'boom' } }

      before do
        allow(TD::Api).to receive(:client_receive).and_return(raw_update)
      end

      it 'warns plainly instead of force-feeding the wrapped object to the @extra waiter' do
        received = []
        manager.add_handler(TD::UpdateHandler.new(TD::Types::Base, 'req-2', disposable: true) { |u| received << u })

        expect { manager.__send__(:handle_update, callback: ->(_u) { raise 'callback bug' }) }
          .to output(/Uncaught exception in update manager: callback bug/).to_stderr

        sleep 0.05
        expect(received).to be_empty
      end
    end
  end
end
