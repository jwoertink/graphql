require "./language"

module GraphQL
  class Schema
    getter document : Language::Document
    @query : QueryType
    @mutation : MutationType?

    # convert JSON value to FValue
    private def to_fvalue(any : JSON::Any) : Language::FValue
      case raw = any.raw
      when Int64
        raw.to_i32.as(Language::FValue)
      when Hash
        args = raw.map do |key, value|
          Language::Argument.new(key, to_fvalue(value))
        end
        Language::InputObject.new(args)
      when Array
        raw.map do |value|
          to_fvalue(value)
        end
      else
        raw.as(Language::FValue)
      end
    end

    private def subtitute_variables(node, variables, errors)
      case node
      when Language::Argument
        case value = node.value
        when Language::VariableIdentifier
          vars = variables
          if !vars.nil? && vars.has_key?(value.name)
            node.value = to_fvalue(vars[value.name])
          else
            errors << Error.new("missing variable #{value.name}", [] of String | Int32)
          end
        when Array
          value.each do |val|
            subtitute_variables(val, variables, errors)
          end
        end
      when Language::InputObject
        node.arguments.each do |arg|
          arg = subtitute_variables(arg, variables, errors)
        end
      end
    end

    def initialize(@query : QueryType, @mutation : MutationType? = nil)
      @document = @query._graphql_document
      if !@mutation.nil?
        @mutation.not_nil!._graphql_document.definitions.each do |definition|
          next unless definition.is_a?(Language::TypeDefinition)
          unless @document.definitions.find { |d| d.is_a?(Language::TypeDefinition) && d.name == definition.name }
            @document.definitions << definition
          end
        end
      end
    end

    def execute(query : String, variables : Hash(String, JSON::Any)? = nil, operation_name : String? = nil, context = Context.new)
      document = Language.parse(query)
      operations = [] of Language::OperationDefinition
      errors = [] of GraphQL::Error

      context.query_type = @query._graphql_type
      context.mutation_type = @mutation.nil? ? nil : @mutation.not_nil!._graphql_type
      context.document = @document

      document.map_children do |node|
        case node
        when Language::OperationDefinition
          operations << node
        when Language::FragmentDefinition
          context.fragments << node
        when Language::Argument
          subtitute_variables(node, variables, errors)
        end
        node
      end

      operation = if !errors.empty?
                    nil
                  elsif operation_name.nil? && operations.size == 1
                    operations.first
                  else
                    if operation_name.nil?
                      errors << Error.new("sent more than one operation but did not set operation name", [] of String | Int32)
                      nil
                    elsif op = operations.find { |q| q.name == operation_name }
                      op
                    else
                      errors << Error.new("could not find operation with name #{operation_name}", [] of String | Int32)
                      nil
                    end
                  end

      JSON.build do |json|
        json.object do
          if !operation.nil? && operation.operation_type == "query"
            json.field "data" do
              json.object do
                errors.concat @query._graphql_resolve(context, operation.selections, json)
              end
            end
          elsif !operation.nil? && !@mutation.nil? && operation.operation_type == "mutation"
            json.field "data" do
              json.object do
                errors.concat @mutation.not_nil!._graphql_resolve(context, operation.selections, json)
              end
            end
          end
          unless errors.empty?
            json.field "errors" do
              errors.to_json(json)
            end
          end
        end
      end
    end
  end
end