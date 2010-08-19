module TinyCore
  module Build
    def build
      @build ||= Dir.chdir RAILS_ROOT do
        revision = `git rev-parse HEAD`
        revision.blank? ? 'unknown' : revision
      end
    end
  end
end
