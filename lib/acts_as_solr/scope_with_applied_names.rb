
if Rails::VERSION::STRING >= "4.1"
  require 'active_record/scoping/named'

  module ::ActiveRecord

    class Relation
      attr_accessor :scopes_applied
    end

    module Scoping
      module Named
        module ClassMethods
          attr_accessor :scopes_applied

          def scope_with_applied_names name, body, &block
            unless body.respond_to?(:call)
              raise ArgumentError, 'The scope body needs to be callable.'
            end

            if dangerous_class_method?(name)
              raise ArgumentError, "You tried to define a scope named \"#{name}\" " \
                "on the model \"#{self.name}\", but Active Record already defined " \
                "a class method with the same name."
            end

            extension = Module.new(&block) if block

            singleton_class.send :define_method, name do |*args|
              scope = all.scoping { body.call(*args) }
              scope = scope.extending(extension) if extension
              scope ||= all

              if scope.respond_to? :scopes_applied
                scope.scopes_applied ||= Set.new
                scope.scopes_applied << name
              end

              scope
            end

          end
          alias_method_chain :scope, :applied_names
        end
      end
    end
  end
elsif Rails::VERSION::STRING >= "3.2"
  require 'active_record/scoping/named'

  module ::ActiveRecord

    class Relation
      attr_accessor :scopes_applied
    end

    module Scoping
      module Named
        module ClassMethods
          attr_accessor :scopes_applied

          def scope_with_applied_names name, scope_options = {}
            name = name.to_sym
            valid_scope_name?(name)
            extension = Module.new(&Proc.new) if block_given?

            scope_proc = lambda do |*args|
              options = scope_options.respond_to?(:call) ? unscoped { scope_options.call(*args) } : scope_options
              options = scoped.apply_finder_options(options) if options.is_a?(Hash)

              relation = scoped.merge(options)
              if relation.respond_to? :scopes_applied
                relation.scopes_applied ||= Set.new
                relation.scopes_applied << name
              end

              extension ? relation.extending(extension) : relation
            end

            singleton_class.send(:redefine_method, name, &scope_proc)
          end
          alias_method_chain :scope, :applied_names

        end
      end
    end
  end
else
  require 'active_record/named_scope'

  module ::ActiveRecord
    module NamedScope
      module ClassMethods

        def named_scope_with_applied_names name, options = {}, &block
          named_scope_without_applied_names name, options, &block

          name = name.to_sym
          scopes[name] = lambda do |parent_scope, *args|
            scope = Scope.new(parent_scope, case options
            when Hash
              options
            when Proc
              if self.model_name != parent_scope.model_name
                options.bind(parent_scope).call(*args)
              else
                options.call(*args)
              end
            end, &block)
            scope.scope_name = name
            scope
          end
        end
        alias_method_chain :named_scope, :applied_names
      end

      class Scope
        attr_accessor :scope_name, :scopes_applied

        def initialize_with_applied_names proxy_scope, options, &block
          initialize_without_applied_names proxy_scope, options, &block
          self.scopes_applied ||= []
          self.scopes_applied += proxy_scope.send :scopes_applied if Scope === proxy_scope

          # unrelated bugfix: use if instead of unless
          if (Scope === proxy_scope || ActiveRecord::Associations::AssociationCollection === proxy_scope)
            @current_scoped_methods_when_defined = proxy_scope.send(:current_scoped_methods)
          end
        end
        alias_method_chain :initialize, :applied_names

        def scope_name= name
          @scope_name = name
          self.scopes_applied << @scope_name
        end

      end

    end
  end
end
