module Mcp
  module Rails
    class Railtie < ::Rails::Railtie
      railtie_name "mcp-rails"
      gem_root = Gem::Specification.find_by_name("mcp-rails").gem_dir

      config.to_prepare do
        require File.join(gem_root, "app/controllers/concerns/mcp/rails/parameters")
        require File.join(gem_root, "app/controllers/concerns/mcp/rails/tool_descriptions")
        ActionController::Base.include(MCP::Rails::Parameters)
        ActionController::Base.include(MCP::Rails::ToolDescriptions)
      end

      rake_tasks do
        path = File.expand_path("#{gem_root}/tasks/mcp", __dir__)
        Dir.glob("#{path}/*.rake").each { |f| load f }
      end
    end
  end
end
