# frozen_string_literal: true

require 'active_record'

RSpec.describe 'ActiveRecord::Relation serialization' do
  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define do
      create_table :fruits, force: true do |t|
        t.string :name
        t.string :secret
      end
    end
  end

  before { ActiveRecord::Base.connection.execute('DELETE FROM fruits') }

  def model(&body)
    Class.new(ActiveRecord::Base) do
      self.table_name = 'fruits'
      class_eval(&body) if body
    end
  end

  def resolve(props)
    InertiaRails::PropsResolver.new(
      props, evaluator: InertiaRails::PropEvaluator.new(Object.new, host: InertiaRails.host), visit: {}
    ).resolve.first
  end

  it 'applies a record to_inertia inside a relation' do
    fruits = model { def to_inertia = { name: name } }
    fruits.create!(name: 'kiwi', secret: 'hidden')

    expect(resolve({ fruits: fruits.all })[:fruits]).to eq([{ name: 'kiwi' }])
  end

  it 'resolves a relation exactly like its to_a' do
    fruits = model { def to_inertia = { name: name } }
    fruits.create!(name: 'kiwi', secret: 'hidden')

    expect(resolve({ fruits: fruits.all })).to eq(resolve({ fruits: fruits.all.to_a }))
  end

  it 'hands records without to_inertia over untouched' do
    fruits = model
    fruits.create!(name: 'fig', secret: 's')

    resolved = resolve({ fruits: fruits.all })[:fruits]

    expect(resolved).to all(be_a(ActiveRecord::Base))
  end

  it 'keeps an app-defined Relation#to_inertia' do
    expect(ActiveRecord::Relation.ancestors).to include(InertiaRails::InertiaRelation)
  end
end
