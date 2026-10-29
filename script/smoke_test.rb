# Dry-run smoke test for machina-template.
#
# Simulates `template.rb`'s `files/` directory copy + APPNAME substitution
# pass without actually running `rails new` (which would take ~10 minutes
# to bundle edge Rails). Reports any APPNAME leftovers and parses every
# generated .rb / .json / YAML file.
#
# Usage:
#   ruby script/smoke_test.rb
#
# Exit code: 0 on success, 1 on any failure.

require "fileutils"
require "tmpdir"
require "yaml"
require "json"
require "open3"
require "rbconfig"

ROOT = File.expand_path("..", __dir__)
SRC  = File.join(ROOT, "files")

abort "Source directory not found: #{SRC}" unless File.directory?(SRC)

failures = []
fail_loud = ->(msg) { failures << msg; warn "  FAIL: #{msg}" }

Dir.mktmpdir do |tmp|
  FileUtils.cp_r("#{SRC}/.", tmp)

  app_name   = "smoketest"
  app_class  = "Smoketest"
  app_dashed = "smoketest"
  port       = "3199"
  domain     = "example.com"

  # 1. Rename APPNAME paths (longest first so nested directories rename correctly)
  Dir.glob("#{tmp}/**/*APPNAME*", File::FNM_DOTMATCH).sort_by(&:length).reverse.each do |path|
    new_path = path.gsub("APPNAME", app_name)
    next if path == new_path
    FileUtils.mkdir_p(File.dirname(new_path))
    FileUtils.mv(path, new_path)
  end

  # 2. Substitute content (matches the regex in template.rb)
  Dir.glob("#{tmp}/**/*", File::FNM_DOTMATCH).each do |path|
    next unless File.file?(path)
    rel = path.sub("#{tmp}/", "")
    next unless rel.match?(/\.(rb|yml|yaml|json|toml|sh|md|erb|gitignore|nvmrc|npmrc|npmignore|dockerignore|ts|tsx|js|html|env\.example)$|(^|\/)(Gemfile|Procfile|Dockerfile|justfile|lefthook\.yml|README|CLAUDE)(\..+)?$|(^|\/)bin\/[^\/]+$|(^|\/)infra\/scripts\/[^\/]+$/)
    body = File.read(path)
    next unless body.include?("APPNAME")
    new_body = body
      .gsub("APPNAME_CLASS", app_class)
      .gsub("APPNAME_DASHED", app_dashed)
      .gsub("APPNAME_PORT", port)
      .gsub("APPNAME_DOMAIN", domain)
      .gsub("APPNAME", app_name)
    File.write(path, new_body) if new_body != body
  end

  puts "── APPNAME leftover check ──"
  Dir.glob("#{tmp}/**/*", File::FNM_DOTMATCH).each do |p|
    next unless File.file?(p)
    rel = p.sub("#{tmp}/", "")
    fail_loud.call("path still contains APPNAME: #{rel}") if rel.include?("APPNAME")
    begin
      fail_loud.call("content still contains APPNAME: #{rel}") if File.read(p).include?("APPNAME")
    rescue
      # binary file or unreadable; skip
    end
  end
  puts "  (no leftovers)" if failures.empty?

  puts
  puts "── YAML parse check ──"
  %w[
    config/machina.yml
    config/queue.yml
    config/cache.yml
    config/cable.yml
    config/bundler-audit.yml
    .github/workflows/ci.yml
  ].each do |p|
    # safe_load (not the default full deserializer behind YAML.load_file) so a
    # template file can never instantiate arbitrary Ruby objects
    # (e.g. `!!ruby/object:...`) while being parsed. `aliases: true` is still
    # allowed because these files use YAML anchors (`<<: *default`).
    Psych.safe_load(File.read("#{tmp}/#{p}"), aliases: true)
    puts "  OK    #{p}"
  rescue => e
    fail_loud.call("YAML parse #{p}: #{e.message}")
  end

  puts
  # Run the syntax check WITHOUT a shell. Passing the file path as a separate
  # argv element means it can never be interpreted as shell syntax. The old
  # backtick version interpolated `p.shellescape rescue p` into a command
  # line that the shell parsed: Shellwords was never required, so #shellescape
  # always raised NoMethodError and the `rescue p` fallback silently fed the
  # RAW, unquoted path to the shell (command injection if a path were ever
  # attacker-controlled, misparse on paths with spaces). Open3.capture3 with
  # argv elements has no shell at all; RbConfig.ruby targets the running
  # interpreter, so the check works even when `ruby` is not on PATH.
  puts "── Ruby syntax check ──"
  rb_files = Dir.glob("#{tmp}/**/*.rb")
  rb_files.each do |p|
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-c", p)
    if status.success?
      next
    else
      out = [stdout, stderr].join.strip
      fail_loud.call("Ruby syntax #{p.sub("#{tmp}/", "")}: #{out}")
    end
  end
  puts "  OK    #{rb_files.size} files"
end

puts
if failures.empty?
  puts "✓ Smoke test passed."
  exit 0
else
  puts "✗ Smoke test FAILED: #{failures.size} issue(s)."
  exit 1
end
