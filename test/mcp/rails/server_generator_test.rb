require "test_helper"

module MCP
  module Rails
    class ServerGeneratorTest < ActiveSupport::TestCase
      def setup
        @temp_dir = Dir.mktmpdir
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
      end

      def teardown
        FileUtils.remove_entry @temp_dir
        MCP::Rails.reset_configuration!
      end

      test "generates server file with correct configuration" do
        generator = MCP::Rails::ServerGenerator
        server_file_paths = generator.generate_files

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
        generator = MCP::Rails::ServerGenerator
        server_file_paths = generator.generate_files

        server_file_paths.each do |server_file_path|
          content = File.read(server_file_path)

          bypass_key = File.read(MCP::Rails.configuration.bypass_key_path).strip
          assert_match(/#{bypass_key}/, content)
        end
      end

      test "generates executable server file" do
        generator = MCP::Rails::ServerGenerator
        server_file_paths = generator.generate_files

        server_file_paths.each do |server_file_path|
          assert File.executable?(server_file_path)
          shebang = File.read(server_file_path).lines.first
          assert_match(/^#!.*ruby/, shebang)
        end
      end

      test "includes base URL in server configuration" do
        MCP::Rails.configure do |config|
          config.base_url = "https://test.example.com"
        end

        generator = MCP::Rails::ServerGenerator
        server_file_paths = generator.generate_files
        content = File.read(server_file_paths.first)

        assert_match("https://test.example.com", content)
      end

      test "regenerates bypass key for each server generation" do
        generator = MCP::Rails::ServerGenerator
        first_server_file_paths = generator.generate_files
        first_content = File.read(first_server_file_paths.first)
        first_key = File.read(MCP::Rails.configuration.bypass_key_path).strip

        # Generate a second server
        generator = MCP::Rails::ServerGenerator
        second_server_file_paths = generator.generate_files
        second_content = File.read(second_server_file_paths.first)
        second_key = File.read(MCP::Rails.configuration.bypass_key_path).strip

        # Keys should be different for each generation
        refute_equal first_key, second_key
        assert_match(/#{second_key}/, second_content)
        refute_match(/#{first_key}/, second_content)
      end
    end
  end
end
