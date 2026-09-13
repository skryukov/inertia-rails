# frozen_string_literal: true

module InertiaRails
  # A relation serializes as its records, so a record's `to_inertia` fires
  # inside `props: { users: User.all }` just as it does inside a plain array.
  module InertiaRelation
    def to_inertia
      to_a
    end
  end
end
