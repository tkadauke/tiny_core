# tiny_core — 2026 Modernization Roadmap

> Opinionated, concrete guidance for bringing `tiny_core` into 2026.
> Written against commit `0fa2d56` (the only commit on `master`).

---

## 1. Executive Summary

- **The gem targets Rails 2.x / Ruby ~1.8 APIs** (`RAILS_ROOT`, `class_inheritable_array`, `request.request_uri`, `ActionController::Base.send :helper`). Every one of these was removed in Rails 3–4. Nothing in this gem runs on any supported Ruby or Rails today.
- **Zero CI, zero lockfile, zero versioning discipline.** There is no `Gemfile`, no `.github/workflows/`, no `.travis.yml`, one test file, and a hardcoded version string `0.0.2` in the gemspec.
- **Migrate to a Rails engine / gem targeting Rails 7.2+ and Ruby 3.3+.** Rewrite the Rails-coupled code as a proper Railtie; replace deprecated APIs; replace `gemmer` with standard Rake + `bundler/gem_tasks`.
- **Adopt strict semantic versioning with an automated release pipeline** (GitHub Actions + `gem-release` or `release-please`). As a shared library, every public API change needs a deprecation cycle and a CHANGELOG entry.
- **Add Dependabot, CodeQL, and SBOM generation from day one.** This is a dependency others pull in — supply-chain hygiene is table-stakes.

---

## 2. Current State

| Dimension | Current |
|---|---|
| Language | Ruby (no version specified; code targets ~1.8 idioms) |
| Framework | Rails 2.3.x (inferred from `dry_plugin_test_helper`, `rails_version: '2.3.3'`, `class_inheritable_array`) |
| Gem version | `0.0.2` (hardcoded in gemspec) |
| Build tool | Rake + `gemmer` (unmaintained, effectively dead) |
| Test framework | Test::Unit via `Rake::TestTask`; 1 test file with 4 test cases |
| CI | None |
| Lockfile | None (`Gemfile` absent) |
| Documentation | A 9-line `README` with no usage examples |
| Release mechanism | `Gemmer::Tasks` → `:release_via :rubygems` (unmaintained) |
| Code quality tooling | None |
| Security tooling | None |
| Container/packaging | None |
| CLAUDE.md | Absent |

### Known API debt

| File | Problem |
|---|---|
| `build.rb` | Uses `RAILS_ROOT` (removed in Rails 3) |
| `config.rb` | Uses `RAILS_ROOT`; re-reads YAML on every call (no caching) |
| `tableless_model.rb` | Inherits `ActiveRecord::Base` for a tableless model; uses `class_inheritable_array` (removed in Rails 3.1); `quoted_id` approach removed in AR 4 |
| `bread_crumb_helper.rb` | Uses `request.request_uri` (removed in Rails 3); uses bare `eval` on URL segments (unsafe) |
| `action_list_helper.rb` | Uses `concat` without `raw`/`html_safe` — XSS risk in modern Rails |
| `rails_ext/attr_protection.rb` | Bypasses `attr_protected` — Rails 4+ strong parameters make this pattern obsolete |
| `rails_ext/dirty_after_save.rb` | `attribute_method_suffix` with an array argument removed in Rails 6 |
| `init.rb` | Rails 2 plugin init style; Rails 3+ uses a Railtie |
| `core_ext/dir.rb` | Uses `Kernel.rand` without seeding, class-level mutable state (`@@creation_number`) |

---

## 3. Recommendations

### 3.1 Language / Runtime / Framework

**Target: Ruby 3.3.x (minimum 3.2), Rails 7.2.x (compatible with 8.0).**

Ruby 3.3 is the current stable release; 3.2 is the oldest branch still receiving security fixes (EOL March 2026 — plan for 3.3 as the floor). Rails 7.2 introduces `config.assume_ssl` and better default security headers; the API surface is stable through Rails 8.

#### Migration path

1. **Add a `Gemfile` and `.ruby-version`** immediately:

   ```ruby
   # Gemfile
   source 'https://rubygems.org'
   gemspec

   group :development, :test do
     gem 'rake',           '~> 13.2'
     gem 'minitest',       '~> 5.24'
     gem 'minitest-reporters', '~> 1.7'
     gem 'rails',          '~> 7.2'
     gem 'activerecord',   '~> 7.2'
     gem 'sqlite3',        '~> 2.1'
   end
   ```

   ```
   # .ruby-version
   3.3.6
   ```

2. **Convert the gem to a Railtie** so it hooks into `config.after_initialize` rather than relying on `init.rb` and global `ActionController::Base.send :helper` calls:

   ```ruby
   # lib/tiny_core/railtie.rb
   require 'rails'

   module TinyCore
     class Railtie < Rails::Railtie
       initializer 'tiny_core.action_view' do
         ActiveSupport.on_load(:action_view) do
           include TinyCore::ActionListHelper
           include TinyCore::BreadCrumbHelper
           include TinyCore::TabsHelper
         end
       end
     end
   end
   ```

3. **Rewrite all deprecated APIs** (full list in §2). Key rewrites:
   - Replace `RAILS_ROOT` with `Rails.root`.
   - Replace `class_inheritable_array` with `class_attribute`.
   - Replace `TablelessModel < ActiveRecord::Base` with `include ActiveModel::Model` + `include ActiveModel::Attributes` — this is what the inline comment already asks for.
   - Replace `request.request_uri` with `request.fullpath`.
   - Replace the `eval`-based breadcrumb lookup with a safe, explicit API.
   - Replace `attribute_method_suffix *array` with individual `attribute_method_suffix` calls.

4. **Remove `gemmer`** from the `Rakefile`; replace with `bundler/gem_tasks`:

   ```ruby
   require 'bundler/gem_tasks'
   require 'rake/testtask'

   Rake::TestTask.new(:test) do |t|
     t.libs   << 'test'
     t.pattern = 'test/**/*_test.rb'
     t.verbose = true
   end

   task default: :test
   ```

5. **Pin a Ruby version matrix** in CI: `['3.2', '3.3']` with Rails `['7.2', '8.0']`.

---

### 3.2 Dependencies

- **Add `Gemfile.lock` to source control** once the `Gemfile` is in place. For a library gem, lock only in development (`Gemfile.lock`) — the gemspec should specify version ranges, not exact pins.
- **Gemspec version constraints:** every runtime dependency must carry an upper-bound pessimistic constraint (`~>`). Currently there are no runtime dependencies declared in the gemspec at all — add `activerecord`, `activesupport`, and `railties` with `>= 7.2, < 9`.
- **Dependency audit:** run `bundle audit` (gem `bundler-audit`) in CI on every push. Add a weekly scheduled run to catch newly published CVEs.
- **Software Composition Analysis (SCA):** enable GitHub's Dependency Graph and activate Dependabot version updates (see §3.6 for the config file).

---

### 3.3 API & Versioning

As a shared library, API stability is the highest-priority concern.

**Adopt Semantic Versioning 2.0.0 strictly.** The current version `0.0.2` signals pre-release instability, which is accurate — but the first public stable release should be `1.0.0`.

#### Before 1.0.0

- Complete the Rails 7.2 migration (§3.1).
- Write a `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format.
- Define and document the public API surface explicitly (yard docs on every public method).

#### Deprecation policy (post-1.0.0)

1. A method or behavior to be removed is marked `@deprecated` in its yard doc.
2. It emits `ActiveSupport::Deprecation.warn` at runtime for one **full minor release cycle**.
3. It is removed in the next major version.
4. The removal is noted under `### Removed` in `CHANGELOG.md`.

#### Breaking-change process

- Breaking changes require a semver major bump (e.g., `1.x.x` → `2.0.0`).
- Open a GitHub Discussion before implementing to allow downstream consumers to comment.
- Provide a migration guide in `docs/migrations/v2.md`.
- Automated release notes are generated by `release-please` (see §3.5).

#### Tooling

```toml
# release-please-config.json
{
  "release-type": "ruby",
  "package-name": "tiny_core",
  "changelog-sections": [
    {"type": "feat",  "section": "Features"},
    {"type": "fix",   "section": "Bug Fixes"},
    {"type": "chore", "section": "Maintenance", "hidden": false},
    {"type": "docs",  "section": "Documentation"}
  ]
}
```

---

### 3.4 Testing

**Current state:** 1 test file, 4 test cases, no CI, Rails 2.3 test environment.

#### Targets

| Metric | Target |
|---|---|
| Line coverage | ≥ 90% (enforced via `simplecov` with `minimum_coverage`) |
| Mutation score | ≥ 70% (Mutant or Stryker-rb) |
| Contract tests | Required for every public helper method |
| Integration tests | Required for Railtie initialization and generator output |

#### Concrete steps

1. **Migrate test harness from `dry_plugin_test_helper` / Rails 2.3 to a minimal Rails 7.2 dummy app** in `test/dummy/`. This is the standard approach for Rails engines:

   ```
   test/
     dummy/          ← generated with `rails plugin new` skeleton
       app/
       config/
     test_helper.rb
     tiny_core/
       action_list_helper_test.rb
       bread_crumb_helper_test.rb
       tabs_helper_test.rb
       config_test.rb
       tableless_model_test.rb
   ```

2. **Add `simplecov`:**

   ```ruby
   # test/test_helper.rb
   require 'simplecov'
   SimpleCov.start 'rails' do
     minimum_coverage 90
     add_filter '/test/'
   end
   ```

3. **Add `minitest-reporters`** for structured CI output:

   ```ruby
   require 'minitest/reporters'
   Minitest::Reporters.use! Minitest::Reporters::DefaultReporter.new(color: true)
   ```

4. **Contract testing:** because consumers include helpers and extend ActiveRecord, use `minitest` with integration assertions against the dummy app rather than a separate contract-test framework. A dedicated `test/contract/` directory should contain tests that exercise the public API as a downstream consumer would — no access to internals.

5. **Mutation testing:** add `mutant` to the development group and a `Rake::Task` named `mutant`:

   ```ruby
   # Rakefile
   begin
     require 'mutant/rake_task'
     Mutant::RakeTask.new do |task|
       task.covered_code_base = 'TinyCore'
       task.integration      = 'minitest'
     end
   rescue LoadError; end
   ```

   Run `bundle exec rake mutant` in CI on pull requests (allow failure in P1, enforce in P2).

---

### 3.5 CI/CD

No CI exists today. Build it from scratch on GitHub Actions.

#### Workflow file: `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:

permissions:
  contents: read

jobs:
  test:
    name: Ruby ${{ matrix.ruby }} / Rails ${{ matrix.rails }}
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        ruby:  ['3.2', '3.3']
        rails: ['7.2', '8.0']

    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - uses: ruby/setup-ruby@32110d4e311bd8996b2a9e4bedc4b9b58b2c5fb9  # v1.207.0
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
        env:
          BUNDLE_GEMFILE: gemfiles/rails_${{ matrix.rails }}.gemfile

      - name: Run tests
        run: bundle exec rake test
        env:
          BUNDLE_GEMFILE: gemfiles/rails_${{ matrix.rails }}.gemfile

      - name: Upload coverage
        uses: codecov/codecov-action@v5
        with:
          token: ${{ secrets.CODECOV_TOKEN }}
```

Use **pinned action SHAs** (never `@v4` floating tags) to prevent supply-chain attacks. The SHAs above are examples — resolve the latest at setup time with `gh release list`.

#### Gemfiles matrix

Create `gemfiles/rails_7.2.gemfile` and `gemfiles/rails_8.0.gemfile` to support the matrix without a single `Gemfile` that tries to satisfy both.

#### Release workflow: `.github/workflows/release.yml`

Use `google-github-actions/release-please-action` (pinned SHA) to automate CHANGELOG generation and gem release:

```yaml
name: Release

on:
  push:
    branches: [master]

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-24.04
    steps:
      - uses: google-github-actions/release-please-action@a37ac6e4f6449ce8b3f7607e4d97d0146028dc0b  # v4.1.3
        id: release
        with:
          release-type: ruby
          package-name: tiny_core
          version-file: lib/tiny_core/version.rb

      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
        if: ${{ steps.release.outputs.release_created }}

      - uses: ruby/setup-ruby@32110d4e311bd8996b2a9e4bedc4b9b58b2c5fb9
        if: ${{ steps.release.outputs.release_created }}
        with:
          ruby-version: '3.3'
          bundler-cache: true

      - name: Publish gem
        if: ${{ steps.release.outputs.release_created }}
        run: bundle exec rake release
        env:
          GEM_HOST_API_KEY: ${{ secrets.RUBYGEMS_API_KEY }}
```

#### OIDC for RubyGems

RubyGems.org supports trusted publishing via OIDC (announced 2024). Configure a trusted publisher on rubygems.org to eliminate the need for long-lived `RUBYGEMS_API_KEY` secrets. This is strictly superior to API keys.

#### Caching

`ruby/setup-ruby` with `bundler-cache: true` handles gem caching automatically. Add explicit caching for the test dummy app's `tmp/` if integration tests become slow.

---

### 3.6 Code Quality

**Current state:** no linter, no formatter, no type checking, no pre-commit hooks.

#### RuboCop

Add `rubocop`, `rubocop-rake`, `rubocop-minitest`, and `rubocop-rails` to the development group. Generate a `.rubocop.yml` with:

```yaml
require:
  - rubocop-rake
  - rubocop-minitest
  - rubocop-rails

AllCops:
  NewCops: enable
  TargetRubyVersion: 3.2
  SuggestExtensions: false

Layout/LineLength:
  Max: 120

Style/Documentation:
  Enabled: false  # re-enable after yard docs are added
```

Run `bundle exec rubocop --autocorrect` initially to fix mechanical violations, then commit the `.rubocop.yml` and enforce clean runs in CI:

```yaml
# in ci.yml jobs:
      - name: Lint
        run: bundle exec rubocop --format github
```

#### Sorbet / RBS type signatures

Add RBS signatures in `sig/` (Ruby 3.x built-in). Do not add Sorbet at this stage — RBS is lower overhead for a gem of this size. Validate with `steep check` in CI.

#### Pre-commit hooks

Add a `.pre-commit-config.yaml` (or use `overcommit`):

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/rubocop/rubocop
    rev: v1.69.1
    hooks:
      - id: rubocop
        args: [--autocorrect]
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-merge-conflict
```

---

### 3.7 Observability

`tiny_core` is a library, not a service — it should not impose a logging framework on consumers. Instead, provide **structured instrumentation hooks via `ActiveSupport::Notifications`** so consumers can subscribe.

```ruby
# lib/tiny_core/instrumentation.rb
module TinyCore
  module Instrumentation
    def self.instrument(event_name, payload = {}, &block)
      ActiveSupport::Notifications.instrument("#{event_name}.tiny_core", payload, &block)
    end
  end
end
```

Document the available notification events in `docs/instrumentation.md`.

#### OpenTelemetry

Do not add an OTel dependency to the gem. Instead, document the pattern for consumers to subscribe via `ActiveSupport::Notifications` and forward to OTel:

```ruby
# In consumer application initializer:
ActiveSupport::Notifications.subscribe(/\.tiny_core$/) do |name, start, finish, id, payload|
  span_name = name.sub('.tiny_core', '')
  OpenTelemetry::SDK.current_tracer.start_span(span_name, ...) { ... }
end
```

---

### 3.8 Security & Supply Chain

| Control | Tool | Action |
|---|---|---|
| Dependency CVE scanning | `bundler-audit` | Add to CI (fail on HIGH+) |
| Dependabot version updates | GitHub Dependabot | Add `.github/dependabot.yml` |
| Secret scanning | GitHub Advanced Security | Enable in repo settings |
| SAST | CodeQL | Add `.github/workflows/codeql.yml` |
| SBOM generation | `syft` | Generate CycloneDX SBOM on release |
| Gem signing | `gem cert` | Sign releases with a maintainer cert |

#### `.github/dependabot.yml`

```yaml
version: 2
updates:
  - package-ecosystem: bundler
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 10
    groups:
      rubocop:
        patterns: ['rubocop*']
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

#### CodeQL workflow: `.github/workflows/codeql.yml`

```yaml
name: CodeQL

on:
  push:
    branches: [master]
  pull_request:
  schedule:
    - cron: '0 8 * * 1'

permissions:
  security-events: write
  contents: read

jobs:
  analyze:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - uses: github/codeql-action/init@ff0a06e83cb2de871e5a09832bc6a81e7276941f  # v3.28.18
        with:
          languages: ruby
      - uses: github/codeql-action/analyze@ff0a06e83cb2de871e5a09832bc6a81e7276941f
```

#### SBOM

Add to the release workflow after `rake release`:

```yaml
      - name: Generate SBOM
        uses: anchore/sbom-action@v0
        with:
          format: cyclonedx-json
          output-file: tiny_core-${{ steps.release.outputs.tag_name }}.sbom.json

      - name: Attach SBOM to release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ steps.release.outputs.tag_name }}
          files: '*.sbom.json'
```

---

### 3.9 Container / Deployment

`tiny_core` is a Ruby gem — it is distributed via RubyGems, not as a container image. Container concerns are therefore minimal.

- **No Docker image required** for the library itself.
- **Add a `Dockerfile.dev`** for the development/CI environment to ensure reproducible test runs:

  ```dockerfile
  FROM ruby:3.3-slim
  WORKDIR /gem
  COPY Gemfile* tiny_core.gemspec ./
  COPY lib/tiny_core/version.rb lib/tiny_core/version.rb
  RUN bundle install
  COPY . .
  CMD ["bundle", "exec", "rake", "test"]
  ```

- If the generator scaffolding (`rails_generators/`) is ever extracted into a standalone service or CLI, add image signing via `cosign` at that point.

---

### 3.10 Developer Experience

**Current state:** no `Gemfile`, no contributor guide, no devcontainer, no editor config.

#### Immediate additions

1. **`CONTRIBUTING.md`** — setup steps, how to run tests, PR expectations, deprecation policy summary.
2. **`.editorconfig`** — enforce 2-space indentation, UTF-8, LF line endings across editors.
3. **`bin/setup`** — idiomatic Bundler setup script:

   ```bash
   #!/usr/bin/env bash
   set -e
   bundle install
   echo "Setup complete. Run 'bundle exec rake test' to run tests."
   ```

4. **`bin/console`** — IRB session with the gem loaded:

   ```ruby
   #!/usr/bin/env ruby
   require 'bundler/setup'
   require 'tiny_core'
   require 'irb'
   IRB.start
   ```

#### Dev Container / GitHub Codespace

Add `.devcontainer/devcontainer.json`:

```json
{
  "name": "tiny_core",
  "image": "mcr.microsoft.com/devcontainers/ruby:3.3",
  "postCreateCommand": "bin/setup",
  "customizations": {
    "vscode": {
      "extensions": [
        "Shopify.ruby-lsp",
        "castwide.solargraph",
        "rebornix.ruby"
      ]
    }
  }
}
```

This lets any contributor open a fully configured environment in Codespaces in under 2 minutes.

#### yard documentation

Add yard and run `bundle exec yardoc` locally and in CI:

```ruby
# Gemfile (development group)
gem 'yard', '~> 0.9'
gem 'redcarpet', '~> 3.6'  # Markdown rendering in yard
```

Publish yard docs to GitHub Pages via a workflow on every release.

---

### 3.11 AI / Agent Readiness

**`CLAUDE.md` is absent.** This is a gap for any agent-assisted development workflow.

Add `CLAUDE.md` at the repo root with the following minimum sections:

```markdown
# CLAUDE.md — tiny_core

## What this repo is
A shared Ruby gem providing helpers and extensions for "Tiny Application" Rails apps.

## How to run tests
bundle exec rake test

## How to lint
bundle exec rubocop

## Key conventions
- Public API methods must have yard doc comments.
- Deprecations use ActiveSupport::Deprecation.warn, not raise.
- All public helper output must be html_safe / use content_tag — no raw string concatenation.
- Do not add runtime dependencies without opening a GitHub Discussion first.

## Architecture
- lib/tiny_core/          — core modules
- lib/tiny_core/helpers/  — ActionView helpers (included via Railtie)
- lib/tiny_core/rails_ext/— ActiveRecord/ActiveSupport extensions
- test/                   — Minitest tests against a Rails dummy app
- rails_generators/       — Legacy Rails 2 generators (to be ported or removed)

## Agent task hints
- When adding a new helper, add it to the Railtie initializer in lib/tiny_core/railtie.rb.
- When changing a public method signature, add a deprecation warning first.
- Run `bundle exec rubocop --autocorrect` before committing.
```

This `CLAUDE.md` makes the repo immediately navigable to any AI agent or new contributor without requiring context from the maintainer.

---

## 4. Prioritized Roadmap

| Priority | Item | Effort | Impact |
|---|---|---|---|
| P0 | Add `Gemfile`, `.ruby-version` (Ruby 3.3), `Gemfile.lock` | XS | Unblocks everything |
| P0 | Remove `gemmer`, replace Rakefile with `bundler/gem_tasks` | XS | Unblocks releases |
| P0 | Add GitHub Actions CI workflow with Ruby 3.2/3.3 matrix | S | Catches regressions |
| P0 | Add `CLAUDE.md` | XS | Agent / contributor readiness |
| P0 | Add Dependabot config | XS | Supply chain hygiene |
| P0 | Pin all action SHAs in CI | XS | Supply chain security |
| P1 | Rewrite all deprecated Rails 2/3 APIs (§3.1 migration list) | L | Gem actually runs on modern Ruby/Rails |
| P1 | Convert `init.rb` → Railtie | M | Proper Rails 7/8 integration |
| P1 | Replace `TablelessModel` with `ActiveModel::Model` | M | Removes AR dependency for tableless records |
| P1 | Add test dummy app, expand test coverage to ≥ 90% | M | Correctness confidence |
| P1 | Add RuboCop + enforce in CI | S | Code quality baseline |
| P1 | Add `simplecov` coverage enforcement | XS | Coverage regression prevention |
| P1 | Add CodeQL workflow | XS | SAST baseline |
| P1 | Add `bundler-audit` to CI | XS | CVE detection |
| P1 | Bump version to `1.0.0` after API rewrite, add `CHANGELOG.md` | S | Semantic versioning start |
| P1 | Add `CONTRIBUTING.md`, `bin/setup`, `bin/console` | S | Developer experience |
| P2 | Set up release-please for automated CHANGELOG + release PRs | M | Release automation |
| P2 | Configure RubyGems OIDC trusted publishing | S | Eliminate API key secrets |
| P2 | Add RBS type signatures + `steep check` in CI | M | Type safety |
| P2 | Add `.devcontainer/` for Codespaces | S | Zero-friction onboarding |
| P2 | Add mutation testing with `mutant` | L | Test quality enforcement |
| P2 | Add `syft` SBOM generation on release | S | Supply chain transparency |
| P2 | Publish yard docs to GitHub Pages | S | API discoverability |
| P2 | Add `ActiveSupport::Notifications` instrumentation hooks | M | Observability for consumers |
| P2 | Add Rails 8.0 to test matrix | XS | Forward compatibility |
| P2 | Port or remove `rails_generators/` (Rails 2 generator API) | M | Remove dead code |

**Effort scale:** XS < 1 day · S = 1–2 days · M = 3–5 days · L = 1–2 weeks

---

## 5. Risks & Non-Goals

### Risks

| Risk | Mitigation |
|---|---|
| **Breaking downstream consumers** during the Rails 2 → Rails 7 migration | Coordinate with known consumers before releasing v1.0.0; use deprecation warnings for any changed public API |
| **`gemmer` removal** may require downstream Rakefile changes | Document the change in `CHANGELOG.md`; `gemmer` is already unmaintained and should not be relied on |
| **`TablelessModel` rewrite** changes serialization semantics | Write contract tests before and after to catch behavioral drift |
| **`BreadCrumbHelper`'s `eval` on URL segments** is a security vulnerability | Remove the `eval` entirely; rewrite as an explicit, allowlist-based approach or remove the helper if unused |
| **No existing consumers are known** | Survey the GitHub dependency graph after the gem is published under the new version to identify real users |

### Non-Goals

- **Do not add a JavaScript build pipeline.** `tiny_core` is a server-side Ruby gem; any frontend helpers should generate static HTML only.
- **Do not add a database migration framework.** The gem provides helpers and extensions, not schema management.
- **Do not add runtime observability (metrics, tracing) as a hard dependency.** Provide hooks; let consumers wire their own OTel/Datadog/etc.
- **Do not target Rails < 7.2.** Supporting older Rails would require maintaining compatibility shims indefinitely. Draw a clean line.
- **Do not sign every commit with GPG** unless the project grows to have multiple committers and a formal release signing policy. It adds process overhead without proportional benefit at this scale.
- **Do not migrate to a monorepo or multi-gem setup yet.** The README mentions the gem "is likely to become very big and be broken up." That split should happen organically once the modules are stable and consumers are identified — not as part of this modernization sprint.
