require 'spec_helper'
require 'tdlib-ruby'

describe TD::TelegramClient do
  let(:fake_client) { instance_double(TD::Client) }

  before do
    allow(TD::Client).to receive(:new).and_return(fake_client)
    allow_any_instance_of(described_class).to receive(:setup_directories)
    allow_any_instance_of(described_class).to receive(:setup_handlers)
  end

  describe '#initialize' do
    it 'forwards per-instance api_id and api_hash into TD::Client when present' do
      described_class.new(api_id: 12_345, api_hash: 'deadbeef')

      expect(TD::Client).to have_received(:new)
        .with(hash_including(api_id: 12_345, api_hash: 'deadbeef'))
    end

    it 'does not pass api_id or api_hash into TD::Client when absent' do
      described_class.new({})

      expect(TD::Client).to have_received(:new) do |kwargs|
        expect(kwargs).not_to have_key(:api_id)
        expect(kwargs).not_to have_key(:api_hash)
      end
    end

    it 'omits only the missing credential when one of the two is given' do
      described_class.new(api_id: 999)

      expect(TD::Client).to have_received(:new) do |kwargs|
        expect(kwargs[:api_id]).to eq(999)
        expect(kwargs).not_to have_key(:api_hash)
      end
    end

    it 'always forwards database_directory and files_directory' do
      described_class.new(database_directory: '/tmp/db', files_directory: '/tmp/files')

      expect(TD::Client).to have_received(:new)
        .with(hash_including(database_directory: '/tmp/db', files_directory: '/tmp/files'))
    end
  end
end
