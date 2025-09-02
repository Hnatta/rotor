#!/bin/sh
# installer.sh — pemasang sekali klik untuk Rotor + Web UI + Modem CLI di OpenWrt
# Pakai:
#   curl -fsSL https://raw.githubusercontent.com/Hnatta/rotor/main/installer.sh | sh
# Atau override sumber:
#   curl -fsSL https://raw.githubusercontent.com/Hnatta/rotor/main/installer.sh | sh -s -- --repo-base https://raw.githubusercontent.com/Hnatta/rotor/main
set -eu

REPO_BASE="https://raw.githubusercontent.com/Hnatta/rotor/main"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-base) REPO_BASE="$2"; shift 2 ;;
    *) echo "Argumen tidak dikenal: $1" >&2; exit 2 ;;
  esac
done

say(){ echo "[installer] $*"; }

# ---------- cek root ----------
if [ "$(id -u)" != "0" ]; then
  say "Harus dijalankan sebagai root"; exit 1
fi

# ---------- paket minimal ----------
need_update=0
ensure_cmd() {
  # $1=binary, $2=pkgname
  if ! command -v "$1" >/dev/null 2>&1; then
    [ $need_update -eq 0 ] && { opkg update || true; need_update=1; }
    opkg install "$2" || true
  fi
}
say "Memeriksa paket: curl jq ca-bundle"
ensure_cmd curl curl
ensure_cmd jq jq
if [ ! -s /etc/ssl/certs/ca-certificates.crt ] && [ ! -s /etc/ssl/cert.pem ]; then
  [ $need_update -eq 0 ] && { opkg update || true; need_update=1; }
  opkg install ca-bundle || true
fi

# ---------- helper unduh ----------
fetch() {
  # $1: src path relatif REPO_BASE, $2: dst path, $3 (opsi): +x untuk chmod
  local src="$1" dst="$2" mode="${3:-}"
  local dir; dir="$(dirname "$dst")"
  [ -d "$dir" ] || mkdir -p "$dir"
  say "Ambil $src -> $dst"
  curl -fsSL "$REPO_BASE/$src" -o "$dst"
  sed -i 's/\r$//' "$dst" 2>/dev/null || true
  [ "$mode" = "+x" ] && chmod +x "$dst"
}

# ---------- ambil file-file ----------
# CLI modem
fetch files/usr/bin/modem /usr/bin/modem +x

# rotor daemon
fetch files/usr/bin/oc-rotor.sh /usr/bin/oc-rotor.sh +x

# env (jangan timpa jika sudah ada)
if [ ! -f /etc/oc-rotor.env ]; then
  fetch files/etc/oc-rotor.env /etc/oc-rotor.env
else
  say "/etc/oc-rotor.env sudah ada — tidak ditimpa"
fi

# service
fetch files/etc/init.d/oc-rotor /etc/init.d/oc-rotor +x

# web ui (nama baru)
fetch files/www/logrotor.html /www/logrotor.html
fetch files/www/yaml.html     /www/yaml.html
# bersihkan nama lama jika masih ada
[ -f /www/rotor-log.html ] && rm -f /www/rotor-log.html
[ -f /www/oc-yaml.html  ] && rm -f /www/oc-yaml.html

# LuCI controller → toolsoc.lua
fetch files/usr/lib/lua/luci/controller/toolsoc.lua /usr/lib/lua/luci/controller/toolsoc.lua
# Bersihkan nama lama jika ada (hindari bentrok)
[ -f /usr/lib/lua/luci/controller/oc-tools.lua ] && rm -f /usr/lib/lua/luci/controller/oc-tools.lua
[ -f /usr/lib/lua/luci/controller/oc_tools.lua ] && rm -f /usr/lib/lua/luci/controller/oc_tools.lua

# ---------- enable services ----------
say "Enable + start service rotor"
/etc/init.d/oc-rotor stop >/dev/null 2>&1 || true
/etc/init.d/oc-rotor enable
/etc/init.d/oc-rotor start

# ---------- cron untuk log web ----------
say "Setup cron untuk update & bersihkan /www/oc-rotor.log"
CR_TMP="/tmp/oc-installer-cron.$$"
crontab -l 2>/dev/null > "$CR_TMP" || true
sed -i '/oc-rotor\.log/d' "$CR_TMP" 2>/dev/null || true
cat >> "$CR_TMP" <<'CRON'
# Update file log untuk web tiap 1 menit (ambil 500 baris terakhir tag oc-rotor)
*/1 * * * *  /bin/sh -c 'logread -e oc-rotor | tail -n 500 > /www/oc-rotor.log'
# Bersihkan file log web tiap 5 menit
*/5 * * * *  /bin/sh -c ': > /www/oc-rotor.log'
CRON
crontab "$CR_TMP"
rm -f "$CR_TMP"

# ---------- reload LuCI & uHTTPd ----------
rm -f /tmp/luci-indexcache 2>/dev/null || true
/etc/init.d/uhttpd reload 2>/dev/null || /etc/init.d/uhttpd restart 2>/dev/null || true

# ---------- ringkasan ----------
CTRL_HINT_IP="$(uci get network.lan.ipaddr 2>/dev/null || echo '192.168.1.1')"
say "Selesai ✅"
cat <<EOF

== Ringkasan ==
- Modem CLI   : /usr/bin/modem   (pakai: modem ip | modem rb | modem sd)
- Rotor       : /usr/bin/oc-rotor.sh (service: /etc/init.d/oc-rotor)
- Env         : /etc/oc-rotor.env  (ubah CTRL/SECRET/GROUPS/PING_URL sesuai sistem)
- Web UI      : http://$CTRL_HINT_IP/yaml.html     (OC D/E — Converter)
                 http://$CTRL_HINT_IP/logrotor.html (OC Ping — Monitor)
- LuCI menu   : Services → OC D/E, Services → OC Ping
- Web Log     : /www/oc-rotor.log (diisi via cron, dibersihkan tiap 5 menit)

Catatan:
1) Pastikan Clash/OpenClash:
   external-controller: 0.0.0.0:9090
   secret: "12345"
   (samakan SECRET di /etc/oc-rotor.env dan di Web UI)
2) Ubah /etc/oc-rotor.env jika perlu, lalu restart rotor:
   /etc/init.d/oc-rotor restart
3) Cek log rotor:
   logread -e oc-rotor | tail -n 50
EOF
