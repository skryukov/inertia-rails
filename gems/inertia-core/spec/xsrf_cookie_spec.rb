# frozen_string_literal: true

RSpec.describe Inertia::Core::XsrfCookie do
  describe '.refresh?' do
    def refresh?(policy, method, cookie, &vouch)
      described_class.refresh?(policy, method, cookie, &vouch)
    end

    it 'always refreshes under :always' do
      expect(refresh?(:always, 'GET', 'tok') { true }).to be true
    end

    it 'refreshes an unsafe request, or one without a cookie, without asking the host' do
      never = ->(_cookie) { raise 'asked' }

      expect(refresh?(:lazy, 'POST', 'tok', &never)).to be true
      expect(refresh?(:lazy, 'GET', nil, &never)).to be true
      expect(refresh?(:lazy, 'HEAD', '  ', &never)).to be true
    end

    it 'lets a safe request keep a cookie the host vouches for' do
      expect(refresh?(:lazy, 'GET', 'tok') { |cookie| cookie == 'tok' }).to be false
      expect(refresh?(:lazy, 'HEAD', 'stale') { |cookie| cookie == 'tok' }).to be true
    end
  end
end
