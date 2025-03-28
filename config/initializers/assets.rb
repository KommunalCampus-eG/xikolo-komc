# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

Rails.application.config.tap do |config|
  # Version of your assets, change this if you want to expire all your assets.
  config.assets.version = '1.0'

  # Use brand specific manifest for sprockets because assets can be overridden
  # in the brand specific path added further down
  config.assets.manifest = Rails.root.join("public/assets/.sprockets.#{Xikolo.brand}.json")

  # Manifest from Webpack
  config.assets_manifest.path = "public/assets/webpack/.manifest.#{Xikolo.brand}.json"
  config.assets_manifest.passthrough = true

  # Add additional assets to the asset load path.

  # Add brand specific path *before* the regular `app/assets` directory to be
  # able to override specific assets such as `logo.png`
  config.paths['app/assets'] = [
    "brand/#{Xikolo.brand}/assets",
    'app/assets',
  ]

  # As a prerequisite for migrating to webpack, we temporarily import certain node modules into sprockets
  config.assets.paths << Rails.root.join('node_modules/bootstrap-sass/assets/javascripts')

  # Add the brand-specific manifest files to the precompile targets.
  # They define which branded files need to be compiled and added to
  # the output.
  if (brand = Rails.root.join("brand/#{Xikolo.brand}/assets/config/brand.js")).exist?
    config.assets.precompile << brand.to_s
  end
end
