#!/bin/sh
# installer.sh — Rotor + Modem CLI + LuCI views + TinyFM PHP
# - logrotor.php opsional (tidak gagal jika 404)
# - cron diaktifkan & dijadwalkan (2 entri)
# - opsi --no-php-setup untuk melewati setup PHP/uHTTPd
set -eu

REPO_BASE="https://raw.githubusercontent.com/Hnatta/rotor/main"
SETUP_PHP=1

say(){ echo "[installer] $*"; }
die(){ echo "[installer][ERR] $*" >&2; exit 1; }

# ---------- argumen ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-base)
      [ $# -ge 2 ] || die "Argumen untuk --repo-base harus diisi"
      REPO_BASE="$2"; shift 2 ;;
    --no-php-setup)
      SETUP_PHP=0; shift 1 ;;
    *)
      die "Argumen tidak dikenal: $1" ;;
  esac
done

# ---------- cek root & platform ----------
[ "$(id -u)" = "0" ] || die "Harus dijalankan sebagai root"
[ -f /etc/openwrt_release ] || say "Peringatan: bukan OpenWrt (lanjutkan jika custom build)"

# ---------- helper pkg ----------
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
# TLS CA
if [ ! -s /etc/ssl/certs/ca-certificates.crt ] && [ ! -s /etc/ssl/cert.pem ]; then
  [ $need_update -eq 0 ] && { opkg update || true; need_update=1; }
  opkg install ca-bundle || true
  [ -s /etc/ssl/certs/ca-certificates.crt ] || [ -s /etc/ssl/cert.pem ] || die "CA bundle tidak tersedia"
fi

# ---------- (opsional) PHP-CGI untuk .php di uHTTPd ----------
if [ "$SETUP_PHP" -eq 1 ]; then
  say "Menyiapkan dukungan PHP-CGI (opsional)"
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
else
  say "Lewati setup PHP-CGI (--no-php-setup)"
fi

# ---------- helper unduh ----------
fetch() {
  # $1: src (relatif REPO_BASE), $2: dst, $3 (opsi): +x
  local src="$1" dst="$2" mode="${3:-}" tmp dir
  dir="$(dirname "$dst")"; [ -d "$dir" ] || mkdir -p "$dir"
  tmp="${dst}.tmp.$$"
  say "Ambil $src -> $dst"
  curl -fSL --retry 3 --retry-delay 1 --connect-timeout 10 \
    "$REPO_BASE/$src" -o "$tmp"
  sed -i 's/\r$//' "$tmp" 2>/dev/null || true
  mv "$tmp" "$dst"
  [ "$mode" = "+x" ] && chmod +x "$dst"
}

fetch_opt() {
  # seperti fetch(), tapi tidak gagal kalau 404/timeout
  local src="$1" dst="$2" mode="${3:-}" tmp dir
  dir="$(dirname "$dst")"; [ -d "$dir" ] || mkdir -p "$dir"
  tmp="${dst}.tmp.$$"
  say "Ambil (opsional) $src -> $dst"
  if curl -fSL --retry 3 --retry-delay 1 --connect-timeout 10 \
       "$REPO_BASE/$src" -o "$tmp"; then
    sed -i 's/\r$//' "$tmp" 2>/dev/null || true
    mv "$tmp" "$dst"
    [ "$mode" = "+x" ] && chmod +x "$dst"
  else
    say "Lewati: $src tidak tersedia (opsional)."
    rm -f "$tmp" 2>/dev/null || true
  fi
}

# ---------- pasang inti ----------
fetch files/usr/bin/modem /usr/bin/modem +x
fetch files/usr/bin/oc-rotor.sh /usr/bin/oc-rotor.sh +x
if [ ! -f /etc/oc-rotor.env ]; then
  fetch files/etc/oc-rotor.env /etc/oc-rotor.env
  chmod 600 /etc/oc-rotor.env
else
  say "/etc/oc-rotor.env sudah ada — tidak ditimpa"
fi
fetch files/etc/init.d/oc-rotor /etc/init.d/oc-rotor +x

# ---------- TinyFM PHP & LuCI Views/Controller ----------
say "Menambahkan TinyFM PHP & LuCI views/controller"
# Web PHP (yaml wajib, logrotor opsional)
fetch files/www/tinyfm/yaml.php         /www/tinyfm/yaml.php
fetch_opt files/www/tinyfm/logrotor.php /www/tinyfm/logrotor.php
# LuCI views (wajib)
fetch files/usr/lib/lua/luci/view/yaml.htm     /usr/lib/lua/luci/view/yaml.htm
fetch files/usr/lib/lua/luci/view/logrotor.htm /usr/lib/lua/luci/view/logrotor.htm
# LuCI controller (wajib)
fetch files/usr/lib/lua/luci/controller/toolsoc.lua /usr/lib/lua/luci/controller/toolsoc.lua

# Bersihkan artefak HTML lama jika ada
[ -f /www/yaml.html ] && rm -f /www/yaml.html
[ -f /www/logrotor.html ] && rm -f /www/logrotor.html
# Bersihkan controller lama yang bentrok
[ -f /usr/lib/lua/luci/controller/oc-tools.lua ] && rm -f /usr/lib/lua/luci/controller/oc-tools.lua
[ -f /usr/lib/lua/luci/controller/oc_tools.lua ] && rm -f /usr/lib/lua/luci/controller/oc_tools.lua

# ---------- cron: enable/start + dua entri ----------
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
- Env         : /etc/oc-rotor.env  [perm 600]
- Web (PHP)   : http://$CTRL_HINT_IP/tinyfm/yaml.php
                (opsional) http://$CTRL_HINT_IP/tinyfm/logrotor.php
- LuCI Views  : /usr/lib/lua/luci/view/{yaml.htm,logrotor.htm}
- LuCI Menu   : Services → OC D/E, Services → OC Ping (controller: toolsoc.lua)
- Web Log     : /www/oc-rotor.log (update tiap 1 menit; truncate tiap 5 menit)

Tips:
- Ubah /etc/oc-rotor.env sesuai sistem, lalu:
/etc/init.d/oc-rotor restart
EOF
