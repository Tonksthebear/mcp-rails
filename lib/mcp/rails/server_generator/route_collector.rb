module MCP
  module Rails
    class ServerGenerator::RouteCollector
      def self.collect_routes(routes, prefix = "", engine = nil)
        routes.map do |route|
          app = route.app.app

          if app.respond_to?(:routes) && app < ::Rails::Engine
            new_prefix = [ prefix, route.path.spec.to_s ].join
            collect_routes(app.app.routes.routes, new_prefix, app)
          else
            path = [ prefix, route.path.spec.to_s ].join
            {
              route: route,
              path: path.present? ? path : route.path.spec.to_s,
              engine: engine
            }
          end
        end.flatten
      end

      def self.process_routes(routes)
        candidate_routes = routes.select do |wrapped_route|
          route = wrapped_route[:route]
          action = route.defaults[:action]&.to_s
          mcp = route.defaults[:mcp]
          mcp == true || (mcp.is_a?(Array) && action&.in?(mcp.map(&:to_s)))
        end

        candidate_routes.map do |wrapped_route|
          route = wrapped_route[:route]
          next unless route.defaults[:controller] && route.defaults[:action]
          next unless route.defaults[:action].to_s.in?(%w[create index show update destroy])
          next if route.verb.downcase == "put"

          begin
            controller_name = route.defaults[:controller].split("/").map(&:camelize).join("::") + "Controller"
            controller_class = controller_name.constantize
            action = route.defaults[:action].to_sym
            params_def = controller_class.permitted_params(action)
          rescue NameError => e
            warn("Controller not found for route: #{route.defaults[:controller]}; #{e.message}")
            next
          end

          full_path = (wrapped_route[:path] || route.path.spec.to_s).sub(/\(\.:format\)$/, "") || ""
          url_params = extract_url_params(full_path)
          params_def += url_params unless params_def.any? { |p| url_params.map { |up| up[:name] }.include?(p[:name]) }

          description = controller_class.tool_description(action) || "Handles #{action} for #{route.defaults[:controller]}"

          {
            tool_name: "#{action}_#{route.defaults[:controller].parameterize}",
            description: escape_for_ruby_string(description),
            method: route.verb.downcase.to_sym,
            path: full_path,
            url_parameters: url_params,
            engine: wrapped_route[:engine],
            accepted_parameters: params_def.map { |param| build_param_structure(param) }
          }
        end.compact
      end

      def self.build_param_structure(param)
        structure = {
          name: param[:name],
          type: param[:type] || :string,
          required: param[:required]
        }
        structure[:item_type] = param[:item_type] if param[:item_type]  # Add item_type for scalar arrays
        structure[:description] = escape_for_ruby_string(param[:example]) if param[:example]
        structure[:nested] = param[:nested].map { |n| build_param_structure(n) } if param[:nested]
        structure
      end

      def self.escape_for_ruby_string(str)
        str.to_s.gsub(/[\\"]/) { |m| "\\#{m}" }
      end

      def self.extract_url_params(path)
        path.scan(/:([a-zA-Z0-9_]+)/).flatten.map { |name| { name: name, type: "string", required: true } }
      end
    end
  end
end
