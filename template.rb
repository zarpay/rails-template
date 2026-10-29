# frozen_string_literal: true

# Opinionated, agent-native Rails application template.
#
# Designed to be run non-interactively by a Claude Code agent or CI script.
#
# Required ENV:
#   MACHINA_PORT — port for bin/dev and the OAuth callback URL. Pick a free
#                  port; do NOT use 3000 (almost always in use on dev machines).
#
# Usage:
#   MACHINA_PORT=3042 rails new myapp \
#     -m /path/to/machina-template/template.rb \
#     --skip-bundle --skip-test --skip-git
#
# See README.md for the full picture.

require "fileutils"

# ──────────────────────────────────────────────────────────────────────────
#  Inputs & validation
# ──────────────────────────────────────────────────────────────────────────

@port = ENV["MACHINA_PORT"]
if @port.nil? || @port.strip.empty?
  abort <<~MSG

    machina-template: MACHINA_PORT is required.

    Pick a port that's not already in use on this machine, then re-run:

      MACHINA_PORT=<port> rails new <app> -m <template-path>

    Quick free-port check:
      lsof -iTCP:3042 -sTCP:LISTEN  # silent = free
      ruby -rsocket -e 'TCPServer.new(3042).close' && echo free

    Do not default to 3000 — it is almost always taken.

  MSG
end
@port = @port.to_i
abort "machina-template: MACHINA_PORT must be a valid port number" unless (1024..65535).cover?(@port)

@app_name             = app_name                 # e.g. "myapp" or "my_app"
@app_class            = app_const_base           # e.g. "Myapp" or "MyApp"
@app_dashed           = @app_name.tr("_", "-")   # e.g. "my-app"
@org_email_domain     = ENV.fetch("MACHINA_ORG_DOMAIN", "example.com")

# Source directory for the verbatim files/ tree shipped alongside this script.
@template_files_root = File.expand_path("files", __dir__)
unless File.directory?(@template_files_root)
  abort "machina-template: companion files/ directory not found at #{@template_files_root}"
end

say "machina-template: generating #{@app_name} (#{@app_class}) on port #{@port}", :green

# ──────────────────────────────────────────────────────────────────────────
#  Gemfile — full replacement
# ──────────────────────────────────────────────────────────────────────────

remove_file "Gemfile"

create_file "Gemfile", <<~RUBY
  source "https://rubygems.org"

  # Bundle edge Rails
  gem "rails", github: "rails/rails", branch: "main"
  # The modern asset pipeline for Rails
  gem "propshaft"
  # SQLite for development/test
  gem "sqlite3", ">= 2.1"
  # PostgreSQL for production
  gem "pg", "~> 1.6"
  # Puma web server
  gem "puma", ">= 5.0"
  # JavaScript with ESM import maps
  gem "importmap-rails"
  # Hotwire's SPA-like page accelerator
  gem "turbo-rails"
  # Hotwire's modest JavaScript framework
  gem "stimulus-rails"
  # Tailwind CSS
  gem "tailwindcss-rails"
  # Build JSON APIs with ease
  gem "jbuilder"

  # Active Model has_secure_password
  gem "bcrypt", "~> 3.1.7"

  # Auth — machina-auth (public gem on rubygems.org). It speaks the Machina
  # Console SSO protocol; point it at your own identity service via
  # MACHINA_IDENTITY_URL, or swap it for Devise / Rails 8 built-in auth /
  # OmniAuth. See docs/DEPLOYMENT.md and the auth notes in README.md.
  gem "machina-auth", "1.0.2", require: "machina"

  # Windows zoneinfo
  gem "tzinfo-data", platforms: %i[ windows jruby ]

  # Database-backed adapters for Rails.cache, Active Job, and Action Cable
  gem "solid_cache"
  gem "solid_queue"
  gem "solid_cable"
  gem "mission_control-jobs"

  # Pagination
  gem "pagy"

  # Service objects
  gem "servus"
  gem "dry-initializer"

  # LLM stack — Raix + OpenRouter + RubyLLM (Claude / OpenAI / Gemini)
  gem "raix", "~> 2.0"
  gem "open_router"
  gem "ruby_llm"

  # HTTP client
  gem "faraday"
  gem "faraday-multipart"
  gem "faraday-retry"

  # Markdown rendering
  gem "redcarpet"

  # Component-based views
  gem "view_component"

  # State machines for AR models
  gem "state_machines-activerecord"

  # Error tracking
  gem "sentry-ruby"
  gem "sentry-rails"

  # Boot performance
  gem "bootsnap", require: false

  # HTTP asset caching/compression and X-Sendfile acceleration in front of Puma
  gem "thruster", require: false

  # Image variants (Active Storage)
  gem "image_processing", "~> 1.2"

  # S3 adapter (production)
  gem "aws-sdk-s3", require: false

  group :development, :test do
    gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

    # Security
    gem "brakeman", require: false
    gem "bundler-audit", require: false

    # Linting
    gem "rubocop-rails-omakase", require: false

    # Testing
    gem "rspec-rails"
    gem "webmock"
    gem "vcr"
  end

  group :development do
    gem "web-console"
    # Foreman drives the Procfile.dev fleet (web + css + worker)
    gem "foreman"
    # Auto-load .env at Rails boot
    gem "dotenv-rails"
  end

  gem "concise_errors", github: "obie/concise_errors"
RUBY

# ──────────────────────────────────────────────────────────────────────────
#  Copy the verbatim files/ tree, then rename placeholder paths
# ──────────────────────────────────────────────────────────────────────────

directory @template_files_root, ".", force: true

# Files whose names contain "APPNAME" need to be renamed to the app name.
# Filenames can't easily contain ERB, so we use a placeholder marker.
inside "." do
  Dir.glob("**/*APPNAME*", File::FNM_DOTMATCH).each do |path|
    new_path = path.gsub("APPNAME", @app_name)
    next if path == new_path
    FileUtils.mkdir_p(File.dirname(new_path))
    FileUtils.mv(path, new_path)
  end
end

# Some shell scripts and templates inside files/ contain the literal "APPNAME"
# token in their contents (used because ERB inside a heavily-quoted shell or
# JSON file is awkward). Replace those tokens.
inside "." do
  Dir.glob("**/*", File::FNM_DOTMATCH).each do |path|
    next unless File.file?(path)
    # Skip binary files
    next unless path.match?(/\.(rb|yml|yaml|json|toml|sh|md|erb|gitignore|nvmrc|npmrc|npmignore|dockerignore|ts|tsx|js|html|env\.example)$|^(Gemfile|Procfile|Dockerfile|justfile|lefthook\.yml|README|CLAUDE|bin\/|infra\/scripts\/)/)

    body = File.read(path)
    next unless body.include?("APPNAME")
    new_body = body
      .gsub("APPNAME_CLASS", @app_class)
      .gsub("APPNAME_DASHED", @app_dashed)
      .gsub("APPNAME_PORT", @port.to_s)
      .gsub("APPNAME_DOMAIN", @org_email_domain)
      .gsub("APPNAME", @app_name)
    File.write(path, new_body) if new_body != body
  end
end

# Make every shipped bin/ script and infra script executable.
%w[
  bin/setup
  bin/ci
  bin/brakeman
  bin/bundler-audit
  bin/docker-entrypoint
].each { |f| File.chmod(0o755, f) if File.exist?(f) }

# ──────────────────────────────────────────────────────────────────────────
#  Migration: create_users
# ──────────────────────────────────────────────────────────────────────────

migration_timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
create_file "db/migrate/#{migration_timestamp}_create_users.rb", <<~RUBY
  class CreateUsers < ActiveRecord::Migration[8.2]
    def change
      create_table :users do |t|
        t.string :email, null: false
        t.string :name
        t.string :provider, null: false
        t.string :uid, null: false
        t.string :avatar_url
        t.string :member_ref

        t.timestamps
      end
      add_index :users, :email, unique: true
      add_index :users, [ :provider, :uid ], unique: true
      add_index :users, :member_ref, unique: true, where: "member_ref IS NOT NULL"
    end
  end
RUBY

# ──────────────────────────────────────────────────────────────────────────
#  Routes — add auth routes above the default health route
# ──────────────────────────────────────────────────────────────────────────

# Rails generated a stub routes.rb. Replace it with ours (which still has
# the default health route, plus auth routes wired to AuthController).
remove_file "config/routes.rb"
create_file "config/routes.rb", <<~RUBY
  Rails.application.routes.draw do
    # Authentication (machina-auth). The engine serves GET /machina/callback,
    # which verifies the login state nonce and sets the session cookie.
    get "login",     to: "auth#login", as: :login
    delete "logout", to: "auth#logout", as: :logout
    mount Machina::Engine => "/machina"

    # Health check (used by ALB target groups + Kamal)
    get "up" => "rails/health#show", as: :rails_health_check

    # Mission Control (background jobs UI). Mount behind authenticated only.
    mount MissionControl::Jobs::Engine, at: "/jobs"

    # Defines the root path route ("/")
    root "home#index"
  end
RUBY

# ──────────────────────────────────────────────────────────────────────────
#  Procfile.dev — uses MACHINA_PORT for `web`
# ──────────────────────────────────────────────────────────────────────────

remove_file "Procfile.dev" if File.exist?("Procfile.dev")
create_file "Procfile.dev", <<~PROCFILE
  web: bin/rails server -p ${PORT:-#{@port}} -b 127.0.0.1
  css: bin/rails tailwindcss:watch
  worker: bin/rails solid_queue:start
PROCFILE

# ──────────────────────────────────────────────────────────────────────────
#  .env.example — documents the env contract
# ──────────────────────────────────────────────────────────────────────────

create_file ".env.example", <<~ENV, force: true
  # Local dev port for bin/dev
  PORT=#{@port}

  # Machina Console (SSO) integration. Point MACHINA_IDENTITY_URL at your own
  # identity service, or remove the auth layer entirely (see README.md).
  MACHINA_PRODUCT_ID=
  MACHINA_SERVICE_TOKEN=
  MACHINA_IDENTITY_URL=http://localhost:3100
  # App public origin; the machina-auth callback (<BASE_URL>/machina/callback) is
  # derived from it. In production set it to your app's public URL.
  BASE_URL=http://localhost:#{@port}

  # Org email domain for User#org_member? checks
  MACHINA_ORG_DOMAIN=#{@org_email_domain}

  # LLM (optional — only needed if the app uses Raix / RubyLLM)
  OPENROUTER_API_KEY=

  # Error tracking (optional)
  SENTRY_DSN=
ENV

# ──────────────────────────────────────────────────────────────────────────
#  config/application.rb adjustments
# ──────────────────────────────────────────────────────────────────────────

inject_into_class "config/application.rb", "Application" do
  <<~CONFIG

    # Don't generate system test files (we use RSpec).
    config.generators.system_tests = nil
  CONFIG
end

# ──────────────────────────────────────────────────────────────────────────
#  After bundle — rspec install, tailwind install, schema load
# ──────────────────────────────────────────────────────────────────────────

after_bundle do
  # `rails new` installs solid_cache / solid_queue / solid_cable by default in
  # Rails 8, so we don't re-run those install generators. Our directory copy
  # already overwrote queue.yml / cache.yml / cable.yml with our versions.

  # rspec:install creates .rspec + spec/spec_helper.rb + spec/rails_helper.rb.
  # Use --force so it doesn't prompt for the conflicts with our shipped versions.
  generate "rspec:install", "--force"

  # Restore our shipped spec/spec_helper.rb and spec/rails_helper.rb after
  # `rspec:install` overwrites them.
  %w[.rspec spec/spec_helper.rb spec/rails_helper.rb].each do |path|
    src = File.join(@template_files_root, path)
    FileUtils.cp(src, path) if File.exist?(src)
  end

  # Tailwind: install if not already installed by `rails new --css=tailwind`.
  rails_command "tailwindcss:install" unless File.exist?("config/tailwind.config.js") || File.exist?("config/tailwind.config.ts")

  rails_command "db:prepare"

  git :init unless File.directory?(".git")
  git add: "."
  git commit: %Q{-m "Initial commit from machina-template"}

  say "", :green
  say "─" * 70, :green
  say "machina-template: #{@app_name} ready.", :green
  say "─" * 70, :green
  say ""
  say "Next steps:"
  say "  cd #{@app_name}"
  say "  cp .env.example .env.local && edit .env.local"
  say "  bin/dev                          # web + css + worker on :#{@port}"
  say ""
  say "Deploying to production:"
  say "  This template is infra-agnostic — bring your own deploy pipeline."
  say "  See docs/DEPLOYMENT.md for what a production setup wires up"
  say "  (Docker image, Postgres, background worker, secrets, health check)."
  say ""
end
