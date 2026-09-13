# frozen_string_literal: true

module InertiaRails
  class LazyProp < IgnoreOnFirstLoadProp
    def initialize(value = nil, &block)
      raise ArgumentError, 'You must provide either a value or a block, not both' if value && block

      InertiaRails.deprecator.warn(
        '`lazy` is deprecated and will be removed in InertiaRails 4.0, use `optional` instead.'
      )

      block ? super(&block) : super(value: value)
    end
  end
end
