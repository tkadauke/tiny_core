# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`tiny_core` is a Ruby gem that bundles common building blocks extracted from a family of small Rails applications ("Tiny Applications"). It provides view helpers, ActiveRecord extensions, a tableless model base class, a YAML-backed config accessor, a git-revision build helper, and a Rails generator that scaffolds an application initializer and version module. The README notes the gem is early-stage and likely to be split into smaller gems later.

## Tech Stack

- Language: Ruby
- Framework: Rails 2.3.x (targets `ActiveRecord::Base`, `ActionController::Base`, `ActionView::TestCase`, uses `RAILS_ROOT`, `class_inheritable_array`, `mattr_accessor`)
- Packaging: RubyGems (`tiny_core.gemspec`), release automation via `gemmer`
- Test framework: `Test::Unit` style via `Rake::TestTask`, plus `mocha` for mocking and `dry_plugin_test_helper` (`PluginTestEnvironment`) to bootstrap a Rails 2.3.3 test environment
- Build tool: Rake
- Docs: RDoc (via `Rake::RDocTask`)

## Repository Structure

- `lib/tiny_core.rb` — top-level loader; `require`s every component file
- `lib/tiny_core/` — gem source
  - `application.rb` — `TinyCore::Application` module with a `name` accessor
  - `build.rb` — `TinyCore::Build` mixin returning the current git HEAD revision from `RAILS_ROOT`
  - `config.rb` — `TinyCore::Config` reads `config/config.yml` and exposes top-level keys via `method_missing`
  - `core_ext/` — extensions to `Dir` and `I18n`
  - `helpers/` — view helpers: `action_list_helper`, `bread_crumb_helper`, `tabs_helper` (auto-registered with `ActionController::Base`)
  - `rails_ext/` — `attr_protection` and `dirty_after_save` mixins included into `ActiveRecord::Base`
  - `search_filter.rb` — small `SearchFilter` PORO with a `query` attribute
  - `tableless_model.rb` — `TinyCore::TablelessModel < ActiveRecord::Base` abstract class with manually declared columns
- `rails_generators/tiny_core/` — Rails 2 generator (`tiny_core_generator.rb`) plus ERB templates (`application.rb`, `version.rb`)
- `test/` — test suite
  - `abstract_unit.rb` — boots the plugin test environment and loads `mocha`
  - `tiny_core/*_test.rb` — per-component tests (currently `action_list_helper_test.rb`)
- `init.rb` — Rails 2 plugin entry point that loads `lib/tiny_core`
- `Rakefile` — defines `test`, `rdoc`, and Gemmer release tasks
- `tiny_core.gemspec` — gem metadata; packages `lib/**/*` and `rails_generators/**/*`
- `README` — short project description

## Common Commands

- Install dependencies: no `Gemfile` is present; install gems used by the Rakefile and tests as needed (`gem install rake gemmer mocha dry_plugin_test_helper`).
- Run tests: `rake test` (also the default task: `rake`)
- Generate RDoc: `rake rdoc`
- Build/release the gem: handled by `Gemmer::Tasks` configured in the `Rakefile` (`t.release_via :rubygems`); see Gemmer for the exact task names.
- Use the Rails generator (in a Rails 2 app with this gem/plugin installed): `script/generate tiny_core <Name>`

## Architecture & Conventions

- Single top-level namespace `TinyCore` with sub-namespaces `Helpers` (implicit via path), `RailsExt`, `Application`, `Build`, `Config`.
- Components self-register on load: helpers call `ActionController::Base.send :helper, ...`, and `rails_ext/attr_protection.rb` does `ActiveRecord::Base.send :include, ...`. Requiring `lib/tiny_core` therefore has side effects on the host Rails app.
- Mixin pattern in `rails_ext`: a module defines `ClassMethods` and `InstanceMethods` and uses an `included` hook to extend/include them onto the receiver.
- `TablelessModel` overrides `create_or_update`, privatizes `quoted_id`, and reimplements `column`/`reset_column_information` to keep an in-memory column list — intended for form-object style records that should not be persisted by id.
- `Config` is a class with `method_missing` that re-reads `config/config.yml` on every call (no caching) and looks up string keys.
- `Build#build` shells out to `git rev-parse HEAD` inside `RAILS_ROOT` and memoizes the result per including object.
- Generator templates use ERB with `<%= class_name %>` and produce `config/initializers/application.rb` and `lib/<file_name>/version.rb` in the host app.

## Testing

- Tests live under `test/` and follow the `*_test.rb` naming convention picked up by the Rakefile pattern `test/**/*_test.rb`.
- `test/abstract_unit.rb` is the shared entry point: it requires `dry_plugin_test_helper` and calls `PluginTestEnvironment.initialize_environment(File.dirname(__FILE__), :rails_version => '2.3.3')`, then loads `mocha`.
- Helper tests subclass `ActionView::TestCase` (e.g. `TinyCore::ActionListHelperTest`) and use the `test "name" do ... end` macro.
- Run the suite with `rake test`.

## Notes / Gotchas

- This gem targets Rails 2.3.x. APIs like `class_inheritable_array`, `RAILS_ROOT`, `Rails::Generator::NamedBase`, and `Rake::RDocTask` are removed or deprecated in modern Rails/Ruby. Do not assume Rails 3+ idioms apply.
- `tableless_model.rb` carries a `# Port me to ActiveModel in Rails 3` comment — intentional tech debt, not a bug to fix incidentally.
- Loading `lib/tiny_core` mutates `ActiveRecord::Base` and `ActionController::Base` globally; be mindful when reasoning about test isolation.
- `lib/tiny_core/search_filter.rb` defines a top-level `SearchFilter` class (not under `TinyCore`), unlike the rest of the gem.
- `Gemfile`, `Gemfile.lock`, `.rubocop.yml`, CI workflows, and similar modern tooling are intentionally absent.
- `Rakefile` requires `gemmer`, so even running `rake test` will fail if `gemmer` is not installed.
