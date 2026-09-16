# frozen_string_literal: true

require 'digest'

class AutomationResponseSelector
  class << self
    def normalized_key(value)
      value.to_s.unicode_normalize(:nfkc).squish.downcase
    end

    def visible_choices(choices)
      choices.to_a.group_by { |choice| normalized_key(choice.label) }.values.map(&:first)
    end

    def random_variant(choices, selected_choice:, seed:)
      key = normalized_key(selected_choice.label)
      variants = choices.to_a.select { |choice| normalized_key(choice.label) == key }
      variants.fetch(stable_index(variants.length, "#{seed}:#{key}"))
    end

    def stable_sample(records, seed:)
      values = records.to_a.sort_by(&:id)
      values.fetch(stable_index(values.length, seed.to_s))
    end

    private

    def stable_index(size, seed)
      raise ArgumentError, 'Cannot select from an empty collection' if size.zero?

      Digest::SHA256.hexdigest(seed).to_i(16) % size
    end
  end
end
