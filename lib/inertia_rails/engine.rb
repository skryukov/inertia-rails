require_relative "middleware"
require_relative "controller"

module InertiaRails
  class Engine < ::Rails::Engine
    initializer "inertia_rails.configure_rails_initialization" do |app|
      app.middleware.use ::InertiaRails::Middleware
    end

    initializer "inertia_rails.action_controller" do
      ActiveSupport.on_load(:action_controller_base) do
        include ::InertiaRails::Controller
      end
    end

    initializer "inertia_rails.subscribe_to_notifications" do
      if Rails.env.development? || Rails.env.test?
        ActiveSupport::Notifications.subscribe('inertia_rails.unoptimized_partial_render', InertiaRails::UnoptimizedPartialReloadHandler.new)
      end
    end
  end
end
