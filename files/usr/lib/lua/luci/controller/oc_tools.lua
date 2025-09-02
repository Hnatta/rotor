module("luci.controller.oc_tools", package.seeall)

function index()
  local fs = require "nixio.fs"
  if not fs then return end

  if fs.access("/www/oc-yaml.html") then
    entry({"admin","services","oc_yaml"}, call("go_yaml"), _("OC D/E"), 10).leaf = true
  end
  if fs.access("/www/rotor-log.html") then
    entry({"admin","services","oc_ping"}, call("go_ping"), _("OC Ping"), 11).leaf = true
  end
end

function go_yaml()
  local http = require "luci.http"
  http.redirect("/oc-yaml.html")
end

function go_ping()
  local http = require "luci.http"
  http.redirect("/rotor-log.html")
end
