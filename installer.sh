#!/bin/sh
# installer.sh — Rotor + Modem CLI + LuCI views + TinyFM PHP
# Instal via OpenWrt terminal (menimpa semua file bila ada):
#   curl -fsSL https://raw.githubusercontent.com/Hnatta/rotor/main/installer.sh | sh
set -eu

REPO_BASE="https://raw.githubusercontent.com/Hnatta/rotor/main"

say(){ echo "[installer] $*"; }
die(){ echo "[installer][ERR] $*" >&2; exit 1; }

# ---------- argumen opsional ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-base) [ $# -ge 2 ] || die "Butuh nilai untuk --repo-base"; REPO_BASE="$2"; shift 2 ;;
    *) die "Argumen tidak dikenal: $1" ;;
  esac
done

# ---------- cek root & platform ----------
[ "$(id -u)" = "0" ] || die "Harus dijalankan sebagai root"
[ -f /etc/openwrt_release ] || say "Peringatan: bukan OpenWrt (lanjut jika custom build)"

# ---------- paket minimal ----------
need_update=0
ensure_pkg_cmd() {
  # $1=binary, $2=pkgname
  if ! command -v "$1" >/dev/null 2>&1; then
    [ $need_update -eq 0 ] && { opkg update || true; need_update=1; }
    opkg install "$2" || true
    command -v "$1" >/dev/null 2>&1 || die "Dependensi '$1' (paket $2) tidak tersedia setelah install"
  fi
}

say "Memeriksa paket: curl + ca-bundle"
ensure_pkg_cmd curl curl
if [ ! -s /etc/ssl/certs/ca-certificates.crt ] && [ ! -s /etc/ssl/cert.pem ]; then
  [ $need_update -eq 0 ] && { opkg update || true; need_update=1; }
  opkg install ca-bundle || true
  [ -s /etc/ssl/certs/ca-certificates.crt ] || [ -s /etc/ssl/cert.pem ] || die "CA bundle tidak tersedia"
fi

# ---------- (opsional) PHP-CGI untuk .php di uHTTPd ----------
say "Menyiapkan PHP-CGI (opsional; best-effort)"
if ! command -v php-cgi >/dev/null 2>&1; then
  [ $need_update -eq 0 ] && { opkg update || true; need_update=1; }
  opkg install php8-cgi || opkg install php7-cgi || true
fi
if command -v uci >/dev/null 2>&1 && [ -f /etc/config/uhttpd ]; then
  if ! uci -q show uhttpd.main.interpreter | grep -q "\.php=/usr/bin/php-cgi"; then
    uci add_list uhttpd.main.interpreter=".php=/usr/bin/php-cgi" 2>/dev/null || true
    uci commit uhttpd 2>/dev/null || true
  fi
  if ! uci -q show uhttpd.main.index_page | grep -q "index.php"; then
    uci add_list uhttpd.main.index_page="index.php" 2>/dev/null || true
    uci commit uhttpd 2>/dev/null || true
  fi
fi

# ---------- helper unduh (timpa + atomic) ----------
fetch() {
  # $1: src (relatif REPO_BASE), $2: dst, $3 (opsi): +x
  local src="$1" dst="$2" mode="${3:-}" tmp dir
  dir="$(dirname "$dst")"; [ -d "$dir" ] || mkdir -p "$dir"
  tmp="${dst}.tmp.$$"
  say "Ambil $src -> $dst"
  curl -fSL --retry 3 --retry-delay 1 --connect-timeout 10 "$REPO_BASE/$src" -o "$tmp"
  sed -i 's/\r$//' "$tmp" 2>/dev/null || true
  mv "$tmp" "$dst"          # timpa selalu
  [ "$mode" = "+x" ] && chmod +x "$dst"
}

# ---------- pasang inti (TIMPA SEMUA) ----------
fetch files/usr/bin/modem /usr/bin/modem +x
fetch files/usr/bin/oc-rotor.sh /usr/bin/oc-rotor.sh +x
fetch files/etc/oc-rotor.env /etc/oc-rotor.env    # timpa env bila ada
chmod 600 /etc/oc-rotor.env
fetch files/etc/init.d/oc-rotor /etc/init.d/oc-rotor +x

# ---------- TinyFM PHP (TIMPA) ----------
fetch files/www/tinyfm/yaml.php     /www/tinyfm/yaml.php
fetch files/www/tinyfm/logrotor.php /www/tinyfm/logrotor.php || true  # jika 404 di repo, hilangkan '|| true' untuk fail-hard

# ---------- LuCI views & controller (TIMPA) ----------
fetch files/usr/lib/lua/luci/view/yaml.htm     /usr/lib/lua/luci/view/yaml.htm
fetch files/usr/lib/lua/luci/view/logrotor.htm /usr/lib/lua/luci/view/logrotor.htm
fetch files/usr/lib/lua/luci/controller/toolsoc.lua /usr/lib/lua/luci/controller/toolsoc.lua

# ---------- bersihkan artefak lama yang bentrok ----------
[ -f /www/yaml.html ] && rm -f /www/yaml.html
[ -f /www/logrotor.html ] && rm -f /www/logrotor.html
[ -f /usr/lib/lua/luci/controller/oc-tools.lua ] && rm -f /usr/lib/lua/luci/controller/oc-tools.lua
[ -f /usr/lib/lua/luci/controller/oc_tools.lua ] && rm -f /usr/lib/lua/luci/controller/oc_tools.lua

# ---------- cron: enable/start + dua entri (tulis & truncate) ----------
if [ -x /etc/init.d/cron ]; then
  /etc/init.d/cron enable || true
  /etc/init.d/cron start  || true
fi
crontab -l > /tmp/mycron 2>/dev/null || true
sed -i '/oc-rotor\.log/d' /tmp/mycron 2>/dev/null || true
cat >> /tmp/mycron <<'CRON'
# Update file log untuk web tiap 1 menit (ambil 500 baris terakhir dari syslog yang memuat tag oc-rotor)
*/1 * * * *  /bin/sh -c 'logread -e oc-rotor | tail -n 500 > /www/oc-rotor.log'
# Bersihkan/truncate file log web tiap 5 menit
*/5 * * * *  /bin/sh -c ': > /www/oc-rotor.log'
CRON
crontab /tmp/mycron 2>/dev/null || true
rm -f /tmp/mycron

# ---------- enable services ----------
say "Enable + start service rotor"
/etc/init.d/oc-rotor stop >/dev/null 2>&1 || true
/etc/init.d/oc-rotor enable
/etc/init.d/oc-rotor start || die "Gagal start service oc-rotor"

# ---------- reload LuCI & uHTTPd ----------
rm -f /tmp/luci-indexcache 2>/dev/null || true
if [ -x /etc/init.d/uhttpd ]; then
  /etc/init.d/uhttpd reload 2>/dev/null || /etc/init.d/uhttpd restart 2>/dev/null || true
fi

# ---------- ringkasan ----------
CTRL_HINT_IP="$(uci get network.lan.ipaddr 2>/dev/null || echo '192.168.1.1')"
say "Selesai ✅"
cat <<EOF

== Ringkasan ==
- Modem CLI   : /usr/bin/modem
- Rotor       : /usr/bin/oc-rotor.sh (service: /etc/init.d/oc-rotor)
- Env         : /etc/oc-rotor.env  [perm 600] (ditimpa dari repo)
- Web (PHP)   : http://$CTRL_HINT_IP/tinyfm/yaml.php
                http://$CTRL_HINT_IP/tinyfm/logrotor.php
- LuCI Views  : /usr/lib/lua/luci/view/{yaml.htm,logrotor.htm}
- LuCI Menu   : Services → OC D/E, Services → OC Ping (controller: toolsoc.lua)
- Web Log     : /www/oc-rotor.log (update tiap 1 menit; truncate tiap 5 menit)
EOF
