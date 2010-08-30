require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'

require 'gemmer'

Gemmer::Tasks.new('tiny_core') do |t|
  t.release_via :rubygems
end

desc 'Default: run unit tests.'
task :default => :test

desc 'Test the tiny_core gem.'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc 'Generate documentation for the tiny_core gem.'
Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'TinyCore'
  rdoc.options << '--line-numbers' << '--inline-source'
  rdoc.rdoc_files.include('README')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
