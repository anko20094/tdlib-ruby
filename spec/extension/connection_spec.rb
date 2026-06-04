require 'spec_helper'
require 'tdlib-ruby'

# The module is included into TD::TelegramClient; @client/@phone are its state.
class DummyConnectionClient
  include TD::Extension::Connection

  def initialize(client:, phone: '+380000000000')
    @client = client
    @phone = phone
  end
end

describe TD::Extension::Connection do
  let(:client) { double('client') }
  let(:connection) { DummyConnectionClient.new(client:) }
  let(:failing_promise) { double('promise') }

  describe 'AUTH_STATE_MAP' do
    it 'maps WaitOtherDeviceConfirmation so the QR-wait branch is reachable' do
      expect(described_class::AUTH_STATE_MAP['WaitOtherDeviceConfirmation'])
        .to eq(:wait_other_device_confirmation)
    end
  end

  describe '#handle_phone_number' do
    context 'when the code request fails' do
      before do
        allow(failing_promise).to receive(:value!).and_raise(StandardError, 'PHONE_NUMBER_BANNED')
        allow(client).to receive(:set_authentication_phone_number).and_return(failing_promise)
      end

      it 're-raises after printing the error so the auth flow halts loudly' do
        expect { connection.__send__(:handle_phone_number) }
          .to raise_error(StandardError, 'PHONE_NUMBER_BANNED')
          .and output(/Failed to request code for \+380000000000: PHONE_NUMBER_BANNED/).to_stdout
      end
    end

    context 'when the code request succeeds' do
      before do
        allow(client).to receive(:set_authentication_phone_number)
          .and_return(double('promise', value!: nil))
      end

      it 'does not raise' do
        expect { connection.__send__(:handle_phone_number) }.not_to raise_error
      end
    end
  end

  describe '#resend_code' do
    context 'when the resend fails' do
      before do
        allow(failing_promise).to receive(:value!).and_raise(StandardError, 'Too Many Requests: retry after 30')
        allow(client).to receive(:resend_authentication_code).and_return(failing_promise)
      end

      it 'prints the error and returns to wait_code instead of swallowing it' do
        expect { connection.__send__(:resend_code) }
          .to output(/Resend failed: Too Many Requests: retry after 30/).to_stdout

        expect(connection.instance_variable_get(:@auth_state)).to eq(:wait_code)
      end
    end
  end

  describe '#handle_code' do
    context 'when the code check fails' do
      before do
        allow($stdin).to receive(:gets).and_return("12345\n")
        allow(failing_promise).to receive(:value!).and_raise(StandardError, 'PHONE_CODE_INVALID')
        allow(client).to receive(:check_authentication_code).and_return(failing_promise)
        allow(client).to receive(:get_authorization_state).and_return(double('promise', value!: nil))
      end

      it 'prints the error and stays in wait_code for a retry' do
        expect { connection.__send__(:handle_code) }
          .to output(/Code check failed: PHONE_CODE_INVALID/).to_stdout

        expect(connection.instance_variable_get(:@auth_state)).to eq(:wait_code)
      end
    end
  end
end
