#!/bin/sh
# installer.sh — pemasang sekali klik untuk Rotor + Web UI + Modem CLI di OpenWrt
# Pakai contoh:
#   curl -fsSL https://raw.githubusercontent.com/Hnatta/rotor/main/installer.sh | sh
# atau:
#   curl -fsSL https://raw.githubusercontent.com/Hnatta/rotor/main/installer.sh | sh -s -- --repo-base https://raw.githubusercontent.com/Hnatta/rotor/main
set -eu

# -------- arg parsing --------
REPO_BASE="https://raw.githubusercontent.com/Hnatta/rotor/main"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-base) REPO_BASE="$2"; shift 2 ;;
    *) echo "Argumen tidak dikenal: $1" >&2; exit 2 ;;
  esac
done

say(){ echo "[installer] $*"; }

# -------- cek root --------
if [ "$(id -u)" != "0" ]; then
  say "Harus dijalankan sebagai root"; exit 1
fi

# -------- paket --------
say "Memasang paket: curl jq ca-bundle (abaikan jika sudah)"
opkg update >/dev/null 2>&1 || true
opkg install curl jq ca-bundle || true

# -------- helper unduh --------
fetch() {
  # arg1: src (relative to REPO_BASE), arg2: dst path, arg3(optional): mode (e.g. +x)
  local src="$1" dst="$2" mode="${3:-}"
  local dir; dir="$(dirname "$dst")"
  [ -d "$dir" ] || mkdir -p "$dir"
  say "Ambil $src -> $dst"
  curl -fsSL "$REPO_BASE/$src" -o "$dst"
  # strip CRLF kalau ada
  sed -i 's/\r$//' "$dst" 2>/dev/null || true
  case "$mode" in
    +x) chmod +x "$dst" ;;
  esac
}

# -------- ambil file-file --------
# Modem CLI
fetch files/usr/bin/modem /usr/bin/modem +x

# Rotor core
fetch files/usr/bin/oc-rotor.sh /usr/bin/oc-rotor.sh +x

# Env (jangan timpa kalau sudah ada)
if [ ! -f /etc/oc-rotor.env ]; then
  fetch files/etc/oc-rotor.env /etc/oc-rotor.env
else
  say "/etc/oc-rotor.env sudah ada — tidak ditimpa"
fi

# Service
fetch files/etc/init.d/oc-rotor /etc/init.d/oc-rotor +x

# Web UI
fetch files/www/rotor-log.html /www/rotor-log.html
fetch files/www/oc-yaml.html  /www/oc-yaml.html

# LuCI controller (menu Services -> OC D/E & OC Ping)
fetch files/usr/lib/lua/luci/controller/oc-tools.lua /usr/lib/lua/luci/controller/oc-tools.lua

# -------- enable services --------
say "Enable + start service rotor"
/etc/init.d/oc-rotor stop >/dev/null 2>&1 || true
/etc/init.d/oc-rotor enable
/etc/init.d/oc-rotor start

# -------- cron untuk update & bersihkan /www/oc-rotor.log --------
say "Setup cron untuk update & bersihkan /www/oc-rotor.log"
CR_TMP="/tmp/oc-installer-cron.$$"
crontab -l 2>/dev/null > "$CR_TMP" || true
# hapus entri lama (idempotent)
sed -i '/oc-rotor\.log/d' "$CR_TMP" 2>/dev/null || true
cat >> "$CR_TMP" <<'CRON'
# Update file log untuk web tiap 1 menit (ambil 500 baris terakhir tag oc-rotor)
*/1 * * * *  /bin/sh -c 'logread -e oc-rotor | tail -n 500 > /www/oc-rotor.log'
# Bersihkan file log web tiap 5 menit
*/5 * * * *  /bin/sh -c ': > /www/oc-rotor.log'
CRON
crontab "$CR_TMP"
rm -f "$CR_TMP"

# -------- reload LuCI & uHTTPd --------
rm -f /tmp/luci-indexcache 2>/dev/null || true
/etc/init.d/uhttpd reload 2>/dev/null || /etc/init.d/uhttpd restart 2>/dev/null || true

# -------- ringkasan --------
CTRL_HINT_IP="$(uci get network.lan.ipaddr 2>/dev/null || echo '192.168.1.1')"
say "Selesai ✅"
cat <<EOF

== Ringkasan ==
- Modem CLI   : /usr/bin/modem   (pakai: modem ip | modem rb | modem sd)
- Rotor       : /usr/bin/oc-rotor.sh (service: /etc/init.d/oc-rotor)
- Env         : /etc/oc-rotor.env  (ubah CTRL/SECRET/GROUPS/PING_URL sesuai sistem)
- Web UI      : http://$CTRL_HINT_IP/oc-yaml.html   (OC D/E — Converter)
                 http://$CTRL_HINT_IP/rotor-log.html (OC Ping — Monitor)
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
