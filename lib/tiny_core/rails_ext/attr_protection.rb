module TinyCore
  module RailsExt
    module AttrProtection
      module ClassMethods
        
      end
      
      module InstanceMethods
        def update_attributes_without_attr_protected(attributes)
          attributes.each do |key, value|
            self.send("#{key}=", value)
          end
          save
        end
      end
      
      def self.included(receiver)
        receiver.extend         ClassMethods
        receiver.send :include, InstanceMethods
      end
    end
  end
end

ActiveRecord::Base.send :include, TinyCore::RailsExt::AttrProtection
