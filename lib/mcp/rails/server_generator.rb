module MCP
  module Rails
    class ServerGenerator
      class << self
        def generate_files(config = MCP::Rails.configuration)
          base_url = config.base_url
          bypass_csrf_key = BypassKeyManager.create_new_key

          all_routes = RouteCollector.collect_routes(::Rails.application.routes.routes).flatten
          grouped_routes = all_routes.group_by { |r| r[:engine] }

          generated_files = []

          # Process main app routes
          main_app_routes = RouteCollector.process_routes(grouped_routes[nil] || [])
          if main_app_routes.any?
            file_path = ServerWriter.write_server(
              main_app_routes,
              config.for_engine(nil),
              base_url,
              bypass_csrf_key
            )
            generated_files << file_path
            ServerWriter.write_wrapper_script(config, file_path, nil)
            generated_files << file_path
          end

          # Process each engine's routes
          grouped_routes.each do |engine, routes|
            next unless engine

            engine_routes = RouteCollector.process_routes(routes)
            next unless engine_routes.any?

            engine_config = config.for_engine(engine)
            file_path = ServerWriter.write_server(
              engine_routes,
              engine_config,
              base_url,
              bypass_csrf_key,
              engine
            )
            generated_files << file_path
            ServerWriter.write_wrapper_script(config, file_path, engine)
            generated_files << file_path
          end

          generated_files
        end
      end
    end
  end
end
