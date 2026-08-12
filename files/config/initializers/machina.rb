# frozen_string_literal: true

# Mount auth AFTER ActionDispatch::Callbacks (which is paired with
# ActionDispatch::Reloader). The Reloader fires Rails.application.reloader.wrap
# on every request, and when a file changed the reloader's class-unload phase
# calls ActiveSupport::CurrentAttributes.reset_all — which wipes
# Machina::Current.authorized. If our middleware ran before the Reloader, the
# auth set on the way in got wiped before the controller saw it, and every
# code-edit-and-reload bounced the browser to /authorize.
Rails.application.config.middleware.insert_after(ActionDispatch::Callbacks, Machina::Middleware::Authentication)

Machina.configure do |config|
  credentials  = Rails.application.credentials.machina || {}
  product_slug = "APPNAME#{Rails.env.production? ? '' : '_dev'}"

  config.manifest      = "config/machina.yml"
  config.product_slug  = product_slug

  config.product_id    = ENV.fetch("MACHINA_PRODUCT_ID", credentials[:product_id])
  config.service_token = ENV.fetch("MACHINA_SERVICE_TOKEN", credentials[:service_token])

  config.identity_service_url  = ENV.fetch("MACHINA_IDENTITY_URL", "http://localhost:3100")

  base_url = ENV.fetch("BASE_URL", "http://localhost:#{ENV.fetch('PORT', APPNAME_PORT)}")
  config.identity_callback_uri = "#{base_url}/machina/callback"

  config.cache_store = Rails.cache
end
