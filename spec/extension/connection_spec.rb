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

  describe '#setup_handlers (QR link rotation)' do
    # The captured handler stands in for the update-manager thread delivering
    # updateAuthorizationState on every Telegram QR-token rotation (~30s).
    def authorization_handler
      handler = nil
      allow(client).to receive(:on) { |_type, &blk| handler = blk }
      connection.setup_handlers
      handler
    end

    def wait_confirmation_update(link)
      TD::Types::Update::AuthorizationState.new(
        authorization_state: TD::Types::AuthorizationState::WaitOtherDeviceConfirmation.new(link: link)
      )
    end

    before { allow(connection).to receive(:system).and_return(false) } # no qrencode in unit env

    it 'prints the fresh QR link on every token rotation' do
      handler = authorization_handler

      expect { handler.call(wait_confirmation_update('tg://login?token=first')) }
        .to output(%r{tg://login\?token=first}).to_stdout
      expect { handler.call(wait_confirmation_update('tg://login?token=second')) }
        .to output(%r{tg://login\?token=second}).to_stdout
    end

    it 'does not reprint an unchanged link' do
      handler = authorization_handler

      expect { handler.call(wait_confirmation_update('tg://login?token=same')) }
        .to output(/token=same/).to_stdout
      expect { handler.call(wait_confirmation_update('tg://login?token=same')) }
        .not_to output(/token=same/).to_stdout
    end

    it 'still maps the state for the auth loop' do
      authorization_handler.call(wait_confirmation_update('tg://login?token=abc'))

      expect(connection.instance_variable_get(:@auth_state)).to eq(:wait_other_device_confirmation)
    end
  end

  describe '#handle_qr_login' do
    context 'when the QR request succeeds' do
      let(:promise) { double('promise', value!: nil) }

      before { allow(client).to receive(:request_qr_code_authentication).and_return(promise) }

      it 'awaits the request result' do
        expect { connection.__send__(:handle_qr_login) }
          .to output(/Qr-code login initiated/).to_stdout

        expect(promise).to have_received(:value!)
      end
    end

    context 'when the QR request fails' do
      before do
        allow(failing_promise).to receive(:value!).and_raise(StandardError, 'Too Many Requests: retry after 30')
        allow(client).to receive(:request_qr_code_authentication).and_return(failing_promise)
      end

      it 're-raises after printing the error instead of waiting for a token that never comes' do
        expect { connection.__send__(:handle_qr_login) }
          .to raise_error(StandardError, 'Too Many Requests: retry after 30')
          .and output(/QR login request failed: Too Many Requests/).to_stdout
      end
    end
  end

  describe '#handle_password' do
    context 'when the password is accepted' do
      let(:promise) { double('promise', value!: nil) }

      before do
        allow($stdin).to receive(:gets).and_return("correct-pass\n")
        allow(client).to receive(:check_authentication_password).with(password: 'correct-pass').and_return(promise)
      end

      it 'awaits the check result' do
        connection.__send__(:handle_password)

        expect(promise).to have_received(:value!)
      end
    end

    context 'when the password is wrong' do
      before do
        allow($stdin).to receive(:gets).and_return("wrong-pass\n")
        allow(failing_promise).to receive(:value!).and_raise(StandardError, 'PASSWORD_HASH_INVALID')
        allow(client).to receive(:check_authentication_password).and_return(failing_promise)
      end

      it 'prints the error and re-arms wait_password instead of swallowing it' do
        expect { connection.__send__(:handle_password) }
          .to output(/Password check failed: PASSWORD_HASH_INVALID/).to_stdout

        expect(connection.instance_variable_get(:@auth_state)).to eq(:wait_password)
      end
    end

    context 'when the password is blank' do
      before { allow($stdin).to receive(:gets).and_return("\n") }

      it 're-arms wait_password instead of hanging the auth loop' do
        expect { connection.__send__(:handle_password) }
          .to output(/Password is blank/).to_stdout

        expect(connection.instance_variable_get(:@auth_state)).to eq(:wait_password)
      end
    end
  end
end
