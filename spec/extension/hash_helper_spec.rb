require 'spec_helper'
require 'tdlib-ruby'

describe TD::Extension::HashHelper do
  describe '.deep_to_hash' do
    it 'converts a typed struct to a string-keyed hash with its TDLib @type restored' do
      struct = TD::Types::ChatType::Supergroup.new(supergroup_id: 42, is_channel: true)

      expect(described_class.deep_to_hash(struct))
        .to eq('@type' => 'chatTypeSupergroup', 'supergroup_id' => 42, 'is_channel' => true)
    end

    it 'restores @type on every nesting level' do
      text = TD::Types::FormattedText.new(
        text: 'hi',
        entities: [
          TD::Types::TextEntity.new(offset: 0, length: 2, type: TD::Types::TextEntityType::Bold.new)
        ]
      )

      hash = described_class.deep_to_hash(text)

      expect(hash['@type']).to eq('formattedText')
      expect(hash['entities'].first['@type']).to eq('textEntity')
      expect(hash['entities'].first['type']).to eq('@type' => 'textEntityTypeBold')
    end

    it 'stringifies keys of plain hashes and converts symbols' do
      expect(described_class.deep_to_hash({ id: 1, 'a' => [{ b: :c }] }))
        .to eq('id' => 1, 'a' => [{ 'b' => 'c' }])
    end

    it 'passes raw force-fed hashes through unchanged' do
      raw = { '@type' => 'message', 'id' => 5, 'media_album_id' => 0 }

      expect(described_class.deep_to_hash(raw)).to eq(raw)
    end
  end

  describe '.get_unknown_structure_data' do
    it 'reads attributes from typed structs and keys from hashes' do
      struct = TD::Types::ChatType::Supergroup.new(supergroup_id: 42, is_channel: false)

      expect(described_class.get_unknown_structure_data(struct, 'supergroup_id')).to eq(42)
      expect(described_class.get_unknown_structure_data({ 'supergroup_id' => 42 }, 'supergroup_id')).to eq(42)
      expect(described_class.get_unknown_structure_data({ supergroup_id: 42 }, 'supergroup_id')).to eq(42)
    end
  end
end
