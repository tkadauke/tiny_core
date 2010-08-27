Gem::Specification.new do |s| 
  s.platform  =   Gem::Platform::RUBY
  s.name      =   "tiny_core"
  s.version   =   "0.0.2"
  s.date      =   Date.today.strftime('%Y-%m-%d')
  s.author    =   "Thomas Kadauke"
  s.email     =   "tkadauke@imedo.de"
  s.summary   =   "Common parts for building Tiny Applications"
  s.files     =   Dir.glob("{lib,rails_generators}/**/*")

  s.require_path = "lib"
end
