module GraphQL::InputObjectType
  macro included
    macro finished
      {% verbatim do %}
      # :nodoc:
      def self._graphql_new(input_object : ::GraphQL::Language::InputObject)
        {% method = @type.methods.find { |m| m.annotation(::GraphQL::Field) } %}
        self.new(
          {% for arg in method.args %}
            {{arg.name.id}}: begin
              arg = input_object.arguments.find{|i| i.name == {{ arg.name.id.stringify.camelcase(lower: true) }}}
              if arg.nil?
                {% if !(arg.default_value.is_a? Nop) %}
                  {{arg.default_value}}
                {% elsif arg.restriction.resolve.nilable? %}
                  nil
                {% else %}
                  raise "missing required input value {{ arg.name.id.camelcase(lower: true) }}"
                {% end %}
              else
                {% arg_type = arg.restriction.resolve.union_types.find { |t| t != Nil }.resolve %}
                {% if arg_type.annotation(::GraphQL::InputObject) %}
                  {% if arg.restriction.resolve.nilable? %}
                    arg.value.nil? ? nil : {{arg_type.id}}._graphql_new(arg.value.as(::GraphQL::Language::InputObject))
                  {% else %}
                    {{arg_type.id}}._graphql_new(arg.value.as(::GraphQL::Language::InputObject))
                  {% end %}
                {% elsif arg_type < Array %}
                  {% if arg_type.type_vars.first.annotation(::GraphQL::InputObject) %}
                  arg.value.as(Array(::GraphQL::Language::ArgumentValue)).map do |value|
                    {{arg_type.type_vars.first.id}}._graphql_new(value.as(::GraphQL::Language::InputObject))
                  end
                  {% else %}
                    arg.value.as(Array(::GraphQL::Language::ArgumentValue)).map {|v| v.as({{arg_type.type_vars.first}}) }
                  {% end %}
                {% else %}
                  arg.value.as({{arg.restriction.resolve}})
                {% end %}
              end
            end,
          {% end %}
        )
      end
      {% end %}
    end
  end
end