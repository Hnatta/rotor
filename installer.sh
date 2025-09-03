#!/bin/sh
# Robust installer — Rotor + Modem CLI + TinyFM PHP + LuCI (pin ke commit terbaru, stub bila 404)
# - Paksa pasang /www/tinyfm/yaml.php dari repo (wajib)
# - Paksa pasang /www/tinyfm/logrotor.php (repo; fallback stub jika 404)
# - Pasang LuCI views (yaml.htm, logrotor.htm) & controller (toolsoc.lua); fallback stub jika 404
# - Aktifkan cron + 2 entri (update 1 menit, truncate 5 menit)
set -eu

OWNER="Hnatta"
REPO="rotor"
REF=""         # auto isi SHA commit terbaru, bisa di-override dengan --ref <sha|tag|branch>
RAW_BASE=""

say(){ echo "[installer] $*"; }
die(){ echo "[installer][ERR] $*" >&2; exit 1; }

# ---------- argumen opsional ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) [ $# -ge 2 ] || die "Butuh nilai untuk --ref"; REF="$2"; shift 2 ;;
    *) die "Argumen tidak dikenal: $1" ;;
  esac
done

# ---------- cek root & platform ----------
[ "$(id -u)" = "0" ] || die "Harus dijalankan sebagai root"
[ -f /etc/openwrt_release ] || say "Peringatan: bukan OpenWrt (lanjut kalau custom build)"

# ---------- pilih commit ----------
if [ -z "$REF" ]; then
  say "Mengambil commit terbaru dari GitHub API…"
  REF="$(curl -fsSL -H 'User-Agent: rotor-installer' \
        "https://api.github.com/repos/${OWNER}/${REPO}/commits?per_page=1" \
        | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p' \
        | head -n1 || true)"
  [ -n "$REF" ] || { say "Gagal ambil SHA terbaru, fallback ke 'main'"; REF="main"; }
fi
RAW_BASE="https://raw.githubusercontent.com/${OWNER}/${REPO}/${REF}"
say "Memakai ref: $REF"

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

# (opsional) PHP-CGI untuk .php di uHTTPd — best effort
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

# ---------- helper unduh ----------
fetch_req(){ # required: fail hard jika 404
  # $1=src relatif, $2=dst, $3(optional)=+x
  local src="$1" dst="$2" mode="${3:-}" tmp dir
  dir="$(dirname "$dst")"; [ -d "$dir" ] || mkdir -p "$dir"
  tmp="${dst}.tmp.$$"
  say "Ambil $src -> $dst"
  curl -fSL --retry 3 --retry-delay 1 --connect-timeout 10 "$RAW_BASE/$src" -o "$tmp"
  sed -i 's/\r$//' "$tmp" 2>/dev/null || true
  mv "$tmp" "$dst"
  [ "$mode" = "+x" ] && chmod +x "$dst"
}

fetch_opt(){ # optional: jika 404, return 1 (caller sediakan stub)
  # $1=src relatif, $2=dst, $3(optional)=+x
  local src="$1" dst="$2" mode="${3:-}" tmp dir
  dir="$(dirname "$dst")"; [ -d "$dir" ] || mkdir -p "$dir"
  tmp="${dst}.tmp.$$"
  say "Ambil (opsional) $src -> $dst"
  if curl -fSL --retry 3 --retry-delay 1 --connect-timeout 10 "$RAW_BASE/$src" -o "$tmp"; then
    sed -i 's/\r$//' "$tmp" 2>/dev/null || true
    mv "$tmp" "$dst"
    [ "$mode" = "+x" ] && chmod +x "$dst"
    return 0
  else
    rm -f "$tmp" 2>/dev/null || true
    return 1
  fi
}

# ---------- pasang inti ----------
fetch_req files/usr/bin/modem /usr/bin/modem +x
fetch_req files/usr/bin/oc-rotor.sh /usr/bin/oc-rotor.sh +x
if [ ! -f /etc/oc-rotor.env ]; then
  fetch_req files/etc/oc-rotor.env /etc/oc-rotor.env
  chmod 600 /etc/oc-rotor.env
else
  say "/etc/oc-rotor.env sudah ada — tidak ditimpa"
fi
fetch_req files/etc/init.d/oc-rotor /etc/init.d/oc-rotor +x

# ---------- TinyFM PHP ----------
# yaml.php: WAJIB dari repo (biar ketahuan kalau repo salah)
fetch_req files/www/tinyfm/yaml.php /www/tinyfm/yaml.php
# logrotor.php: usahakan ambil; kalau 404 → buat stub
if ! fetch_opt files/www/tinyfm/logrotor.php /www/tinyfm/logrotor.php ; then
  say "logrotor.php tidak ada di ref $REF — membuat stub"
  cat > /www/tinyfm/logrotor.php <<'PHP'
<?php
header('Content-Type: text/plain; charset=UTF-8');
$log = '/www/oc-rotor.log';
if (file_exists($log)) { readfile($log); }
else { http_response_code(404); echo "Log tidak ditemukan: $log\n"; }
PHP
fi

# ---------- LuCI views & controller (ambil; jika 404 → stub minimal) ----------
# yaml.htm
if ! fetch_opt files/usr/lib/lua/luci/view/yaml.htm /usr/lib/lua/luci/view/yaml.htm ; then
  say "yaml.htm tidak ada — membuat stub"
  mkdir -p /usr/lib/lua/luci/view
  cat > /usr/lib/lua/luci/view/yaml.htm <<'HTM'
<%+header%>
<h2>OC D/E (YAML)</h2>
<iframe src="/tinyfm/yaml.php" style="width:100%;height:80vh;border:0;"></iframe>
<%+footer%>
HTM
fi
# logrotor.htm
if ! fetch_opt files/usr/lib/lua/luci/view/logrotor.htm /usr/lib/lua/luci/view/logrotor.htm ; then
  say "logrotor.htm tidak ada — membuat stub"
  mkdir -p /usr/lib/lua/luci/view
  cat > /usr/lib/lua/luci/view/logrotor.htm <<'HTM'
<%+header%>
<h2>OC Ping — Log</h2>
<iframe src="/tinyfm/logrotor.php" style="width:100%;height:80vh;border:0;"></iframe>
<%+footer%>
HTM
fi
# controller toolsoc.lua
if ! fetch_opt files/usr/lib/lua/luci/controller/toolsoc.lua /usr/lib/lua/luci/controller/toolsoc.lua ; then
  say "toolsoc.lua tidak ada — membuat stub"
  mkdir -p /usr/lib/lua/luci/controller
  cat > /usr/lib/lua/luci/controller/toolsoc.lua <<'LUA'
module("luci.controller.toolsoc", package.seeall)
function index()
  entry({"admin","services","oc_de"},   template("yaml"),     _("OC D/E"),  20).dependent=false
  entry({"admin","services","oc_ping"}, template("logrotor"), _("OC Ping"), 21).dependent=false
end
LUA
fi

# Bersihkan artefak lama yang bentrok
[ -f /www/yaml.html ] && rm -f /www/yaml.html
[ -f /www/logrotor.html ] && rm -f /www/logrotor.html
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
- Ref dipakai : ${REF}
- Modem CLI   : /usr/bin/modem
- Rotor       : /usr/bin/oc-rotor.sh (service: /etc/init.d/oc-rotor)
- Env         : /etc/oc-rotor.env  [perm 600]
- Web (PHP)   : http://$CTRL_HINT_IP/tinyfm/yaml.php
                http://$CTRL_HINT_IP/tinyfm/logrotor.php
- LuCI Views  : /usr/lib/lua/luci/view/{yaml.htm,logrotor.htm}
- LuCI Menu   : Services → OC D/E, Services → OC Ping (controller: toolsoc.lua)
- Web Log     : /www/oc-rotor.log (update tiap 1 menit; truncate tiap 5 menit)
EOF
