module("luci.controller.toolsoc", package.seeall)

function index()
  -- Menu Services → OC D/E (YAML)
  entry({"admin", "services", "yaml"},
        template("yaml"), _("OC D/E"), 10).leaf = true

  -- Menu Services → OC Ping (Logrotor)
  entry({"admin", "services", "logrotor"},
        template("logrotor"), _("OC Ping"), 11).leaf = true
end
