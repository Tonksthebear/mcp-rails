module MCP
  module Rails
    class ServerGenerator::ServerWriter
      def self.write_server(routes_data, config, base_url, bypass_csrf_key, engine = nil)
        # Get engine-specific configuration if available
        config = config.for_engine(engine)

        file_name = engine ? "#{config.server_name}_server.rb" : "server.rb"
        file_path = File.join(config.output_directory.to_s, file_name)
        FileUtils.mkdir_p(File.dirname(file_path))

        File.open(file_path, "w") do |file|
          file.puts ruby_invocation
          file.puts
          file.puts %(require "mcp")
          file.puts %(require "httparty")
          file.puts
          file.puts helper_methods(base_url, bypass_csrf_key, bearer_token)
          file.puts

          file.puts %(name "#{config.server_name}")
          file.puts %(version "#{config.server_version}")

          routes_data.each do |route|
            file.puts %(tool "#{route[:tool_name].underscore}" do)
            file.puts "  description \"#{route[:description].sub(/\//, ' ')}\""
            route[:accepted_parameters].each do |param|
              file.puts generate_parameter(param)
            end
            file.puts route_block(route, config).lines.map { |line| "  #{line}" }.join
            file.puts "end"
            file.puts
          end
        end

        current_mode = File.stat(file_path).mode
        new_mode = current_mode | 0111  # Add execute (u+x, g+x, o+x)
        File.chmod(new_mode, file_path)

        file_path
      end

      def self.type_to_class(type)
        case type
        when :string then "String"
        when :integer then "Integer"
        when :number then "Float"
        when :boolean then "TrueClass"
        when :array then "Array"
        else "String"  # Default to String
        end
      end

      def self.bearer_token
        "Bearer #{ENV["MCP_API_KEY"]}" if ENV["MCP_API_KEY"]
      end

      def self.generate_parameter(param, indent_level = 1)
        indent = "  " * indent_level
        name = param[:name].to_sym
        required = param[:required] ? ", required: true" : ""
        description = param[:description] ? ", description: \"#{param[:description]}\"" : ""

        if param[:type] == :array
          if param[:item_type]
            # Scalar array: argument :name, Array, items: Type
            type_str = "Array, items: #{type_to_class(param[:item_type])}"
            "#{indent}argument :#{name}, #{type_str}#{required}#{description}"
          elsif param[:nested]
            # Array of objects: argument :name, Array do ... end
            nested_params = param[:nested].map { |np| generate_parameter(np, indent_level + 1) }.join("\n")
            "#{indent}argument :#{name}, Array#{required}#{description} do\n#{nested_params}\n#{indent}end"
          else
            raise "Array parameter must have either item_type or nested parameters"
          end
        elsif param[:type] == :object && param[:nested]
          # Object: argument :name do ... end
          nested_params = param[:nested].map { |np| generate_parameter(np, indent_level + 1) }.join("\n")
          "#{indent}argument :#{name}#{required}#{description} do\n#{nested_params}\n#{indent}end"
        else
          # Scalar type: argument :name, Type
          type_str = type_to_class(param[:type])
          "#{indent}argument :#{name}, #{type_str}#{required}#{description}"
        end
      end

      def self.ruby_invocation
        <<~RUBY
          #!/usr/bin/env ruby

          # Find the nearest Gemfile by walking up the directory tree
          def find_nearest_gemfile(start_dir)
            current_dir = File.expand_path(start_dir)
            loop do
              gemfile = File.join(current_dir, "Gemfile")
              return gemfile if File.exist?(gemfile)
              parent_dir = File.dirname(current_dir)
              break if parent_dir == current_dir # Reached root (e.g., "/")
              current_dir = parent_dir
            end
            nil # No Gemfile found
          end

          # If not already running under bundle exec, re-execute with the nearest Gemfile
          unless ENV["BUNDLE_GEMFILE"] # Check if already running under Bundler
            gemfile = find_nearest_gemfile(__dir__) # __dir__ is the script's directory
            if gemfile
              ENV["BUNDLE_GEMFILE"] = gemfile
              exec("bundle", "exec", "ruby", __FILE__, *ARGV) # Re-run with bundle exec
            else
              warn "Warning: No Gemfile found in any parent directory."
            end
          end
        RUBY
      end

      def self.helper_methods(base_uri, bypass_csrf_key, bearer_token)
        return test_helper_methods(base_uri, bypass_csrf_key) if ::Rails.env.test?
        <<~RUBY
          def transform_args(args)
            if args.is_a?(Hash)
              args.transform_keys { |key| key.to_s.gsub(/([a-z])([A-Z])/, '\\1_\\2').gsub(/([A-Z])([A-Z][a-z])/, '\\1_\\2').downcase }
                .transform_values { |value| transform_args(value) }
            else
              args # Return non-hash values (e.g., strings, integers) unchanged
            end
          end

          def parse_response(response)
            response_body = JSON.parse(response.body)
            case response_body
            when Hash
              if response_body["status"] == "error"
                raise "From Rails Server: \#{response_body["message"]}"
              else
                response_body.dig("data").to_json
              end
            else
              raise "None MCP response from Rails Server"
            end
          rescue => e
            raise "Parsing JSON failed: \#{e.message}"
          end

          def headers
            headers = { "Accept" => "application/vnd.mcp+json, application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            headers["Authorization"] = "#{bearer_token}"
            headers
          end

          def get_resource(uri, arguments = {})
            response = HTTParty.get("#{base_uri}\#{uri}", query: transform_args(arguments), headers:)
            parse_response(response)
          end

          def post_resource(uri, payload = {})
            response = HTTParty.post("#{base_uri}\#{uri}", body: transform_args(payload), headers:)
            parse_response(response)
          end

          def patch_resource(uri, payload = {})
            response = HTTParty.patch("#{base_uri}\#{uri}", body: transform_args(payload), headers:)
            parse_response(response)
          end

          def delete_resource(uri, payload = {})
            response = HTTParty.delete("#{base_uri}\#{uri}", body: transform_args(payload), headers:)
            parse_response(response)
          end
        RUBY
      end

      def self.route_block(route, config)
        uri = route[:path]
        route[:url_parameters].each do |url_parameter|
          uri = uri.gsub(":#{url_parameter[:name]}", "\#{args[:#{url_parameter[:name]}]}")
        end

        env_vars = config.env_vars.map do |var|
          "args[:#{var.downcase}] = ENV['#{var}']"
        end.join("\n")

        method = route[:method].to_s.downcase
        helper_method = "#{method}_resource"

        <<~RUBY
          call do |args|
            #{env_vars}
            #{helper_method}("#{uri}", args)
          end
        RUBY
      end

      def self.test_helper_methods(base_uri, bypass_csrf_key)
        <<~RUBY
          def parse_response(test_context)
            # Would be url: #{base_uri}
            parsed_body = JSON.parse(test_context.response.body)
            case parsed_body
            when Hash
              if parsed_body["status"] == "error"
                raise "From Rails Server: \#{parsed_body["message"]}"
              else
                parsed_body.dig("data")
              end
            else
              raise "None MCP response from Rails Server"
            end
          rescue => e
            raise "Parsing JSON failed: \#{e.message}"
          end

          def get_resource(uri, arguments = {})
            test_context = arguments.delete(:test_context)
            test_context.get uri, params: arguments, headers: { "Accept" => "application/vnd.mcp+json, application/json" }, as: :mcp
            parse_response(test_context)
          end

          def post_resource(uri, payload = {}, headers = {})
            test_context = payload.delete(:test_context)
            headers = { "Accept" => "application/vnd.mcp+json, application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            test_context.post uri, params: payload, headers: headers, as: :mcp
            parse_response(test_context)
          end

          def patch_resource(uri, payload = {})
            test_context = payload.delete(:test_context)
            headers = { "Accept" => "application/vnd.mcp+json, application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            test_context.patch uri, params: payload.merge(headers: headers), as: :mcp
            parse_response(test_context)
          end

          def delete_resource(uri, payload = {})
            test_context = payload.delete(:test_context)
            headers = { "Accept" => "application/vnd.mcp+json, application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            test_context.delete uri, params: payload.merge(headers: headers), as: :mcp
            parse_response(test_context)
          end
        RUBY
      end
    end
  end
end
