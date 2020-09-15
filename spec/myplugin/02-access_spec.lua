local helpers = require "spec.helpers"


local PLUGIN_NAME = "myplugin"


local strategies = {} do
  for _, strategy in helpers.each_strategy() do
    strategies[#strategies + 1] = strategy
  end
  strategies[#strategies + 1] = "off"
end

-- creates a temporary declarative config file from the current db contents
-- @param strategy db strategy to use
-- @return filename of config file when strategy is `off`, otherwise `nil`
helpers.write_declarative_config = function(strategy)
  if strategy ~= "off" then
    return
  end

  local filename="/tmp/kong_test_config.yml"
  os.remove(filename)
  assert(helpers.kong_exec("config db_export "..filename))
  return filename
end


--for _, strategy in helpers.each_strategy() do
for _, strategy in ipairs(strategies) do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()

      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- Inject a test route. No need to create a service, there is a default
      -- service which will echo the request.
      local route1 = bp.routes:insert({
        hosts = { "test1.com" },
      })
      -- add the plugin to test to the route we created
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {},
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,
        -- load declarative config if 'database=off' (returns 'nil' if not 'off')
        declarative_config = helpers.write_declarative_config(strategy),
        -- mess up DB config in case of db-less, as confirmation it is really db-less
        pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
        cassandra_contact_points = strategy == "off" and "unknownhost.konghq.com" or nil,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)



    describe("request", function()
      it("gets a 'hello-world' header", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com"
          }
        })
        -- validate that the request succeeded, response status 200
        assert.response(r).has.status(200)
        -- now check the request (as echoed by mockbin) to have the header
        local header_value = assert.request(r).has.header("hello-world")
        -- validate the value of that header
        assert.equal("this is on a request", header_value)
      end)
    end)



    describe("response", function()
      it("gets a 'bye-world' header", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com"
          }
        })
        -- validate that the request succeeded, response status 200
        assert.response(r).has.status(200)
        -- now check the response to have the header
        local header_value = assert.response(r).has.header("bye-world")
        -- validate the value of that header
        assert.equal("this is on the response", header_value)
      end)
    end)

  end)
end
