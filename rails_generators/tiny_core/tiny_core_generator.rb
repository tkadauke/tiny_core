class TinyCoreGenerator < Rails::Generator::NamedBase
  def manifest
    record do |m|
      m.directory 'config/initializers'
      m.directory File.join('lib', file_name)

      m.template "application.rb", 'config/initializers/application.rb'
      m.template "version.rb", File.join('lib', file_name, 'version.rb')
    end
  end
end
