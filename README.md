# MCP-Rails

**Enhance Rails routing and parameter handling for LLM agents with MCP (Model Context Protocol) integration.**

`mcp-rails` is a Ruby on Rails gem that builds on top of the [mcp-rb](https://github.com/funwarioisii/mcp-rb) library to seamlessly integrate MCP (Model Context Protocol) servers into your Rails application. It enhances Rails routes by allowing you to tag them with MCP-specific metadata and generates a valid Ruby MCP server (in `tmp/mcp/server.rb`), and wrapper script (in `tmp/mcp/server.sh`) that LLM agents, such as Goose, Claude Desktop, and Cline, can connect to. Additionally, it provides a powerful way to define and manage strong parameters in your controllers, which doubles as both MCP server configuration and Rails strong parameter enforcement.

This was inspired during the creation of [Gaggle](https://github.com/Tonksthebear/gaggle).

---

## Features

- **Tagged Routes**: Tag Rails routes with `mcp: true` or specific actions (e.g., `mcp: [:index, :create]`) to expose them to an MCP server.
- **Automatic MCP Server Generation**: Generates a Ruby MCP server in `tmp/mcp/server.rb` for LLM agents to interact with your application.
- **Parameter Definition**: Define permitted parameters in controllers with rich metadata (e.g., types, examples, required flags) that are used for both MCP server generation and Rails strong parameters.
- **HTTP Bridge for LLM Agents**: Generates a ruby based MCP server to interact with your application through HTTP requests, ensuring LLM agents follow the same paths as human users.
- **Environment Variable Integration**: Automatically includes specified environment variables in MCP tool calls.

---

## Installation

Add this line to your application's `Gemfile`:

```ruby
gem 'mcp-rails'
```

Then run:

```bash
bundle install
```

Note, the `mcp-rb` gem will also be installed, which `mcp-rails` depends upon.

---

## Configuration

MCP-Rails can be configured in an initializer file. Create `config/initializers/mcp_rails.rb`:

```ruby
MCP::Rails.configure do |config|
  # Server Configuration
  config.server_name = "my-app-server"      # Default: 'mcp-server'
  config.server_version = "2.0.0"           # Default: '1.0.0'

  # Output Configuration
  config.output_directory = Rails.root.join("tmp/mcp")  # Default: Rails.root.join('tmp', 'mcp')
  config.bypass_key_path = Rails.root.join("tmp/mcp/bypass_key.txt")  # Default: Rails.root.join('tmp', 'mcp', 'bypass_key.txt')

  # Environment Variables
  config.env_vars = ["API_KEY", "ORGANIZATION_ID"]  # Default: ['API_KEY', 'ORGANIZATION_ID']

  # Base URL Configuration
  config.base_url = "http://localhost:3000"  # Default: Uses action_mailer.default_url_options
end
```

If you are an engine developer, you can register your engine's configuration with MCP-Rails:

```ruby
MCP::Rails.configure do |config|
  config.register_engine(YourEngine, env_vars: ["YOUR_ENGINE_KEY"])
end
```

### Environment Variables

The `env_vars` configuration option specifies which environment variables should be automatically included in every MCP tool call. For example, if you configure:

```ruby
config.env_vars = ["API_KEY", "ORGANIZATION_ID"]
```

Then every MCP tool call will automatically include these environment variables as parameters:

```ruby
# If ENV['API_KEY'] = 'xyz123' and ENV['ORGANIZATION_ID'] = '456'
# A tool call like:
create_channel(name: "General")
# Will effectively become:
create_channel(name: "General", api_key: "xyz123", organization_id: "456")
```

This is useful for automatically including authentication tokens, organization IDs, or other environment-specific values in your MCP tool calls without explicitly defining them in your controller parameters.

### Base URL

The base URL for API requests is determined in the following order:

1. Custom configuration via `config.base_url = "http://example.com"`
2. Rails `action_mailer.default_url_options` settings
3. Default fallback to `"http://localhost:3000"`

---

## Usage

### 1. Tagging Routes

In your `config/routes.rb`, tag routes that should be exposed to the MCP server:

```ruby
Rails.application.routes.draw do
  resources :channels, mcp: true # Exposes all RESTful actions to MCP
  # OR
  resources :channels, mcp: [:index, :create] # Exposes only specified actions
end
```

### 2. Defining Parameters

In your controllers, use the `permitted_params_for` DSL to define parameters for MCP actions. These definitions serve a dual purpose: they configure the MCP server and enable strong parameter enforcement in Rails.

Example:

```ruby
class ChannelsController < ApplicationController
  # Define parameters for the :create action
  permitted_params_for :create do
    param :channel, required: true do
      param :name, type: :string, example: "Channel Name", required: true
      param :user_ids, type: :array, item_type: :string, example: ["1", "2"]
    end
  end

  def create
    @channel = Channel.new(resource_params) # Automatically uses the defined params
    if @channel.save
      render json: @channel, status: :created
    else
      render json: @channel.errors, status: :unprocessable_entity
    end
  end
end
```

The LLM will now provide the exact parameters you're used to with default rails routes, inluding the nesting of resources. For example, the LLM will create a channel with the following params

```json
{ channel: { name: "Channel Name", user_ids: ["1", "2"] } }
```

- **MCP Server**: The generated `tmp/mcp/server.rb` will include these parameters, making them available to LLM agents.
- **Rails Strong Parameters**: Calling `resource_params` in your controller action automatically permits and fetches the defined parameters.

### 3. MCP Response Format

MCP-Rails registers a custom MIME type `application/vnd.mcp+json` for MCP-specific responses. This enables:

- Automatic key camelization for MCP protocol compatibility
- Standardized response wrapping with status and data
- View template fallbacks

#### View Templates

You can create MCP-specific views using the `.mcp.jbuilder` extension:

```ruby
# app/views/channels/show.mcp.jbuilder
json.name @channel.name
json.user_ids @channel.user_ids
```

If an MCP view doesn't exist, it will automatically fall back to the corresponding `.json.jbuilder` view:

```ruby
# app/views/channels/show.json.jbuilder
json.name @channel.name
json.user_ids @channel.user_ids
```

#### Explicit Rendering

You can also render MCP responses directly in your controllers:

```ruby
class ChannelsController < ApplicationController
  def show
    @channel = Channel.find(params[:id])

    respond_to do |format|
      format.json { render json: @channel }
      format.mcp  { render mcp: @channel }  # Keys will be automatically camelized
    end
  end
end
```

#### Response Format

All MCP responses are automatically wrapped in a standardized format:

```json
{
  "status": 200,
  "data": {
    "name": "General",
    "userIds": ["1", "2"]  # Note: automatically camelized
  }
}
```

This format ensures compatibility with the generated MCP server

### 4. Customizing Tool Descriptions

By default, MCP-Rails generates tool descriptions in the format "Handles [action] for [controller]". You can customize these descriptions to be more specific and informative using the `tool_description_for` method in your controllers:

```ruby
class ChannelsController < ApplicationController
  tool_description_for :create, "Create a new channel with the specified name and members"
  tool_description_for :index, "List all available channels"
  tool_description_for :show, "Get detailed information about a specific channel"

  # ... rest of controller code
end
```

These descriptions will be used when generating the MCP server, making it clearer to LLM agents what each endpoint does.

### 5. Using the MCP Server

To integrate your MCP server into an MCP client, such as Gaggle, Claude Desktop, Cline, etc we first need to generate a local CLI wrapper app, which will proxy the LLM MCP requests onwards to the Rails app's MCP API endpoints.

After tagging routes and defining parameters, and each time after adding or modifying the routes, run

```bash
bin/rails mcp:rails:generate_server
```

Three files will be generated:

- `tmp/mcp/server.sh` - hard-codes environment variables for the current Ruby/Gems environment
- `tmp/mcp/server.rb` - describes the available MCP tools, and proxies them to the Rails server, which defaults to <http://localhost:3000>
- `tmp/mcp/bypass_key.txt` - used to match to `X-Bypass-CSRF` header values

The MCP server will be generated in `tmp/mcp/server.rb`. The server.rb is an executable that attempts to find the closest Gemfile to the file and executes the server using that Gemfile.

If any engines are registered, the server will be generated for each engine as well.

LLM agents can now connect to this server and interact with your application via HTTP requests.

For an agent like Goose, you can use this new server with

```plain
goose session --with-extension "path_to/tmp/mcp/server.sh"
```

For Claude Desktop, edit the `claude_desktop_config.json` file and pass the full path to `tmp/mcp/server.sh` as the `"command"`.

For example,

```json
{
  "globalShortcut": "",
  "mcpServers": {
    "test_mcp_server": {
      "command": "/home/me/apps/test-mcp-server/tmp/mcp/server.sh"
    }
  }
}
```

---

## Testing Your MCP Server

MCP-Rails provides a test helper module that makes it easy to integration test your MCP server responses. The helper automatically handles server generation, initialization, and cleanup while providing convenient methods to simulate MCP tool calls.

### Setup

Include the test helper in your test class:

```ruby
require "mcp/rails/test_helper"

class MCPChannelTest < ActionDispatch::IntegrationTest
  include MCP::Rails::TestHelper
end
```

The helper automatically:

- Creates a temporary directory for server files
- Configures MCP-Rails to use this directory
- Generates the MCP server files
- Cleans up after each test

### Available Methods

- `mcp_servers`: Returns all generated MCP servers (main app and engines)
- `mcp_server(name: "mcp-server")`: Returns a specific server by name
- `mcp_response_body`: Returns the body of the last MCP response
- `mcp_tool_list(server)`: Gets the list of available tools from a server
- `mcp_tool_call(server, name, arguments = {})`: Makes a tool call to the server

### Example Usage

```ruby
class MCPChannelTest < ActionDispatch::IntegrationTest
  include MCP::Rails::TestHelper

  test "creates a channel via MCP" do
    server = mcp_server

    mcp_tool_call(
      server,
      "create_channel",
      channel: { name: "General", user_ids: ["1", "2"] }
    )

    assert_equal false, mcp_response_body.dig(:result, :isError)
    assert_equal "Channel created successfully", mcp_response_body.dig(:result, :message)
  end
end
```

This approach allows you to verify that your MCP server correctly handles requests and integrates properly with your Rails application.

---

## How It Works

1. **Route Tagging**: The `mcp` option in your routes tells `mcp-rails` which endpoints to expose to the MCP server.
2. **Parameter Definition**: The `permitted_params_for` block defines the structure and metadata of parameters, which are used to generate the MCP server's API and enforce strong parameters in Rails.
3. **Server Generation**: `mcp-rails` leverages `mcp-rb` to create a Ruby MCP server in `tmp/mcp/server.rb`, translating tagged routes and parameters into an interface for LLM agents.
4. **HTTP Integration**: The generated server converts MCP tool calls into HTTP requests, allowing you to reuse all of the same logic for interacting with your application.

---

## Bypassing CSRF Protection

The MCP server generates new HTTP requests on the fly. In standard Rails applications, this is protected by a CSRF (Cross-Site Request Forgery) key that is provided to the client during normal interactions. Since we can't leverage this, `mcp-rails` will generate a unique key to bypass this protection. This is a rudementary way to provide protection and should not be depended upon in production. As such, the gem will not automatically skip this protection on your behalf. You will have to add the following to your `ApplicationController`:

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
    skip_before_action :verify_authenticity_token, if: :mcp_invocation?
end
```

The server adds a `X-Bypass-CSRF` header to all requests. This token gets regenerated and re-applied every time the server is generated. The key is stored in `/tmp/mcp/bypass_key.txt`

## Example

### Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  resources :channels, only: [:index, :create], mcp: true

  resources :posts, mcp: [:create]
end
```

### Controller

```ruby
# app/controllers/channels_controller.rb
class ChannelsController < ApplicationController
  permitted_params_for :create do
    param :channel, required: true do
      param :name, type: :string, example: "General Chat", required: true
      param :goose_ids, type: :array, example: ["goose-123", "goose-456"]
    end
  end

  def index
    @channels = Channel.all
    render json: @channels
  end

  def create
    @channel = Channel.new(resource_params)
    if @channel.save
      render json: @channel, status: :created
    else
      render json: @channel.errors, status: :unprocessable_entity
    end
  end
end
```

### Generated MCP Server

The `tmp/mcp/server.rb` file will include an MCP server that exposes `/channels` (GET) and `/channels` (POST) with the defined parameters, allowing an LLM agent to interact with your app.

For use with something like [Goose](https://github.com/block/goose):

```bash
goose session --with-extension "ruby path_to/tmp/mcp/server.rb"
```

---

## Requirements

- Ruby 3.0 or higher
- Rails 7.0 or higher
- `mcp-rb` gem

---

## Contributing

Bug reports and pull requests are welcome! Please submit them to the [GitHub repository](https://github.com/yourusername/mcp-rails).

1. Fork the repository.
2. Create a feature branch (`git checkout -b my-new-feature`).
3. Commit your changes (`git commit -am 'Add some feature'`).
4. Push to the branch (`git push origin my-new-feature`).
5. Create a new pull request.

---

## License

This gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

---

## Acknowledgments

- Built on top of the excellent `mcp-rb` library.
- Designed with LLM agents like Goose, Claude Desktop, Cline, etc in mind.

---
