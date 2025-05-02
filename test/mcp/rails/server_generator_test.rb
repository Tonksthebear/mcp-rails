require "test_helper"

module MCP
  module Rails
    class ServerGeneratorTest < ActiveSupport::TestCase
      def setup
        @temp_dir = Dir.mktmpdir nil, ::Rails.root.join("tmp")
        @key_path = File.join(@temp_dir, "bypass_key.txt")
        @output_dir = File.join(@temp_dir, "server.rb")

        MCP::Rails.configure do |config|
          config.bypass_key_path = @key_path
          config.output_directory = @output_dir
          config.base_url = "http://example.com:3000"
          config.server_name = "test-server"
          config.server_version = "1.0.0"
          config.env_vars = [ "TEST_API_KEY" ]
        end

        @generator = MCP::Rails::ServerGenerator
      end

      def teardown
        FileUtils.remove_entry @temp_dir
        MCP::Rails.reset_configuration!
      end

      test "generates server file with correct configuration" do
        server_file_paths = @generator.generate_files

        server_file_paths.each do |server_file_path|
          assert File.exist?(server_file_path)
          content = File.read(server_file_path)

          # Verify basic server configuration
          assert_match(/name \"test-server\"/, content)
          assert_match(/version \"1.0.0\"/, content)

          # Verify environment variables are included
          assert_match(/TEST_API_KEY/, content)
        end
      end

      test "includes bypass key in generated server" do
        server_file_paths = @generator.generate_files

        server_file_paths.each do |server_file_path|
          content = File.read(server_file_path)

          bypass_key = File.read(@key_path).strip
          assert_match(/#{bypass_key}/, content)
        end
      end

      test "generates executable server file" do
        server_file_paths = @generator.generate_files

        server_file_paths.each do |server_file_path|
          assert File.executable?(server_file_path)
          shebang = File.read(server_file_path).lines.first
          assert_match(/^#!.*ruby/, shebang)
        end
      end

      test "includes base URL in server configuration" do
        MCP::Rails.configuration.base_url = "https://test.example.com"
        server_file_paths = @generator.generate_files
        content = File.read(server_file_paths.first)

        assert_match("https://test.example.com", content)
      end

      test "regenerates bypass key for each server generation" do
        first_server_file_paths = @generator.generate_files
        first_content = File.read(first_server_file_paths.first)
        first_key = File.read(@key_path).strip

        # Generate a second server
        second_server_file_paths = @generator.generate_files
        second_content = File.read(second_server_file_paths.first)
        second_key = File.read(@key_path).strip

        # Keys should be different for each generation
        refute_equal first_key, second_key
        assert_match(/#{second_key}/, second_content)
        refute_match(/#{first_key}/, second_content)
      end

      test "includes routes from dummy app" do
        server_file_paths = @generator.generate_files
        content = File.read(server_file_paths.first)

        # Verify channels routes are included
        assert_match(/channels/, content)
      end

      test "includes parameter definitions from controllers" do
        server_file_paths = @generator.generate_files
        content = File.read(server_file_paths.first)

        # Verify channel parameter definitions
        assert_match(/argument :channel, required: true/, content)
        assert_match(/argument :name, String/, content)
        assert_match(/argument :user_ids, Array/, content)
        assert_match(/description: "Channel Name"/, content)
        assert_match(%(description: \"[\\\"item1\\\", \\\"item2\\\"]\"), content)
      end

      test "includes custom tool descriptions from controllers" do
        server_file_paths = @generator.generate_files
        content = File.read(server_file_paths.first)

        # Verify custom descriptions are included
        assert_match(/description "List all channels"/, content)
        assert_match(/description "Handles create for channels"/, content)
      end

      test "excludes non-MCP routes" do
        server_file_paths = @generator.generate_files
        content = File.read(server_file_paths.first)

        # Health check route should not be included as it's not marked with mcp: true
        refute_match(/rails_health_check/, content)
      end

      test "generates server with correct HTTP methods" do
        server_file_paths = @generator.generate_files
        content = File.read(server_file_paths.first)

        # Verify HTTP methods for channels routes
        assert_match(/get.*channels/, content)  # index
        assert_match(/post.*channels/, content) # create
      end

      test "handles nested route parameters correctly" do
        server_file_paths = @generator.generate_files
        content = File.read(server_file_paths.first)

        nested_parameters = <<~RUBY
            argument :channel, required: true do
              argument :name, String, required: true, description: "Channel Name"
              argument :user_ids, Array, items: String, description: "[\"1\", \"2\"]"
            end
        RUBY
        nested_parameters = nested_parameters.gsub(/\s+/, "").gsub(/\\"/, '"')
        normalized_content = content.gsub(/\s+/, "").gsub(/\\"/, '"')
        assert_match(nested_parameters, normalized_content)
      end

      test "generates executable wrapper script with correct content" do
        server_rb_paths = @generator.generate_files
        refute_empty server_rb_paths, "No server files were generated"

        server_rb_paths.each do |server_rb_path|
          wrapper_sh_path = server_rb_path.sub(/\.rb$/, ".sh")

          assert File.exist?(wrapper_sh_path), "Wrapper script #{wrapper_sh_path} does not exist"
          assert File.executable?(wrapper_sh_path), "Wrapper script #{wrapper_sh_path} is not executable"

          content = File.read(wrapper_sh_path)

          # Verify shebang
          assert_match(/^#!\/bin\/bash/, content.lines.first)

          # Verify environment variable exports (basic check for presence)
          assert_match(/^export BUNDLE_GEMFILE=/, content)
          assert_match(/^export GEM_HOME=/, content)
          assert_match(/^export GEM_PATH=/, content)
          assert_match(/^export BUNDLE_PATH=/, content)
          assert_match(/^export PATH=.*:\$PATH/, content) # Check if Ruby bin dir is added to PATH
          assert_match(/^export LANG=en_US\.UTF-8/, content)
        end
      end
    end
  end
end
