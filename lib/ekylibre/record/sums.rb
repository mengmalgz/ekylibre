module Ekylibre::Record
  module Sums #:nodoc:

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods


      # Sums columns and puts result in "Parent" table without validations or callbacks.
      def sums(target, children, *args)
        options = {}
        for arg in args
          if arg.is_a? Symbol or arg.is_a? String
            options[arg.to_sym] = arg.to_sym
          elsif arg.is_a? Hash
            options.merge!(arg)
          else
            raise ArgumentError, "Unvalid type #{arg.inspect}:#{arg.class.name}"
          end
        end
        method_name = options.delete(:method) || "sums_#{children}_in_#{target}"
        target_reflection = self.reflections[target]
        target_id = target_reflection.foreign_key.to_sym
        record = children.to_s.singularize
        code = ""
        callbacks = (options.delete(:callbacks) || [:after_save, :after_destroy])
        for callback in callbacks
          code << "#{callback} :#{method_name}\n"
          # code << "#{callback} do\n"
          # code << "  return if self.#{target_id}.to_i.zero?\n"
          # code << "  "+options.collect{|k, v| v}.join(" = ")+" = 0\n"
          # code << "  self.class.where(#{target_id}: self.#{target_id}).find_each do |#{record}|\n"
          # for k, v in options
          #   code << "    #{v} += "+(k.is_a?(Symbol) ? "#{record}.#{k}" : k)+"\n"
          # end
          # code << "  end\n"
          # code << "  " + Ekylibre::Schema.references(self.name.underscore.to_sym, target_id).to_s.camelcase + ".where(id: self.#{target_id}).update_all(" + options.collect{|k, v| ":#{v} => #{v}"}.join(", ") + ")\n"
          # code << "end\n"
        end

        code << "def #{method_name}\n"
        code << "  return unless self.#{target}\n"
        code << "  " + options.values.join(" = ") + " = 0\n"
        # code << "  #{self.name}.where(#{target_id}: self.#{target_id}).find_each do |#{record}|\n"
        # code << "  #{self.name}.where(#{target_id}: self.#{target_id}).find_each do |#{record}|\n"
        code << "  #{target}.#{children}.find_each do |#{record}|\n"
        for k, v in options
          code << "    #{v} += " + (k.is_a?(Symbol) ? "#{record}.#{k}" : k) + "\n"
        end
        code << "  end\n"
        # code << "  " + Ekylibre::Schema.references(self.name.underscore.to_sym, target_id).to_s.camelcase + ".where(id: self.#{target_id}).update_all(" + options.collect{|k, v| "#{v}: #{v}"}.join(", ") + ")\n"
        # code << "  " + target_reflection.class_name + ".where(id: self.#{target_id}).update_all(" + options.collect{|k, v| "#{v}: #{v}"}.join(", ") + ")\n"
        code << "  #{target}.update_columns(" + options.collect{|k, v| "#{v}: #{v}"}.join(", ") + ")\n"
        code << "end\n"

        # code.split("\n").each_with_index{|l, x| puts((x+1).to_s.rjust(4)+": "+l)}

        class_eval code
      end


    end
  end
end

Ekylibre::Record::Base.send(:include, Ekylibre::Record::Sums)
