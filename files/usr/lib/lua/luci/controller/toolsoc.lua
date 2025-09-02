module("luci.controller.toolsoc", package.seeall)

function index()
  local fs = require "nixio.fs"
  if not fs then return end

  -- OC D/E → yaml.html
  if fs.access("/www/yaml.html") then
    entry({"admin","services","oc_yaml"}, call("go_yaml"), _("OC D/E"), 10).leaf = true
  end

  -- OC Ping → logrotor.html
  if fs.access("/www/logrotor.html") then
    entry({"admin","services","oc_ping"}, call("go_ping"), _("OC Ping"), 11).leaf = true
  end
end

function go_yaml()
  local http = require "luci.http"
  http.redirect("/yaml.html")
end

function go_ping()
  local http = require "luci.http"
  http.redirect("/logrotor.html")
end
