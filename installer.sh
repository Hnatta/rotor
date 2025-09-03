#!/bin/sh
# installer.sh — Rotor + Modem CLI + LuCI views + TinyFM PHP (pin ke commit terbaru)
set -eu

OWNER="Hnatta"
REPO="rotor"
REPO_REF=""    # akan diisi SHA commit terbaru, kecuali di-override --ref
RAW_BASE=""    # https://raw.githubusercontent.com/$OWNER/$REPO/$REPO_REF

say(){ echo "[installer] $*"; }
die(){ echo "[installer][ERR] $*" >&2; exit 1; }

# ---------- argumen ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --ref)
      [ $# -ge 2 ] || die "Argumen untuk --ref harus diisi"
      REPO_REF="$2"; shift 2 ;;
    *)
      die "Argumen tidak dikenal: $1" ;;
  esac
done

# ---------- cek root & platform ----------
[ "$(id -u)" = "0" ] || die "Harus dijalankan sebagai root"
[ -f /etc/openwrt_release ] || say "Peringatan: bukan OpenWrt (lanjutkan jika custom build)"

# ---------- tentukan commit terbaru (jika --ref tidak diberikan) ----------
if [ -z "${REPO_REF}" ]; then
  say "Mengambil commit terbaru dari GitHub API…"
  # Catatan: tanpa jq; parsing sederhana dengan sed. Tambah User-Agent biar tidak 403.
  REPO_REF="$(curl -fsSL -H 'User-Agent: rotor-installer' \
    "https://api.github.com/repos/${OWNER}/${REPO}/commits?per_page=1" \
    | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p' \
    | head -n1 || true)"
  # fallback jika API gagal / rate-limit
  [ -n "$REPO_REF" ] || { say "Gagal ambil SHA terbaru, fallback ke 'main'"; REPO_REF="main"; }
fi
RAW_BASE="https://raw.githubusercontent.com/${OWNER}/${REPO}/${REPO_REF}"
say "Memakai ref: ${REPO_REF}"

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

# ---------- helper unduh ----------
fetch() {
  # $1: src path relatif dari root repo (mis. files/usr/bin/modem)
  # $2: dst path, $3 (opsi): +x untuk chmod
  local src="$1" dst="$2" mode="${3:-}" tmp dir
  dir="$(dirname "$dst")"; [ -d "$dir" ] || mkdir -p "$dir"
  tmp="${dst}.tmp.$$"
  say "Ambil $src -> $dst"
  curl -fSL --retry 3 --retry-delay 1 --connect-timeout 10 \
    "$RAW_BASE/$src" -o "$tmp"
  sed -i 's/\r$//' "$tmp" 2>/dev/null || true
  mv "$tmp" "$dst"
  [ "$mode" = "+x" ] && chmod +x "$dst"
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
# Web PHP: yaml.php WAJIB ada pada commit ini (gagal bila 404)
fetch files/www/tinyfm/yaml.php /www/tinyfm/yaml.php

# Web PHP: logrotor.php WAJIB — jika tidak ada di commit ini, buat STUB
mkdir -p /www/tinyfm
if ! curl -fSL --retry 3 --retry-delay 1 --connect-timeout 10 \
     "$RAW_BASE/files/www/tinyfm/logrotor.php" -o /www/tinyfm/logrotor.php.tmp 2>/dev/null; then
  say "logrotor.php tidak ada di ref ${REPO_REF} — membuat stub"
  cat > /www/tinyfm/logrotor.php.tmp <<'PHP'
<?php
header('Content-Type: text/plain; charset=UTF-8');
$log = '/www/oc-rotor.log';
if (file_exists($log)) { readfile($log); }
else { http_response_code(404); echo "Log tidak ditemukan: $log\n"; }
PHP
fi
sed -i 's/\r$//' /www/tinyfm/logrotor.php.tmp 2>/dev/null || true
mv /www/tinyfm/logrotor.php.tmp /www/tinyfm/logrotor.php

# LuCI views & controller
fetch files/usr/lib/lua/luci/view/yaml.htm     /usr/lib/lua/luci/view/yaml.htm
fetch files/usr/lib/lua/luci/view/logrotor.htm /usr/lib/lua/luci/view/logrotor.htm
fetch files/usr/lib/lua/luci/controller/toolsoc.lua /usr/lib/lua/luci/controller/toolsoc.lua

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
# hapus entri lama yang terkait agar tidak duplikat
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
- Ref dipakai : ${REPO_REF}
- Modem CLI   : /usr/bin/modem
- Rotor       : /usr/bin/oc-rotor.sh (service: /etc/init.d/oc-rotor)
- Env         : /etc/oc-rotor.env  [perm 600]
- Web (PHP)   : http://$CTRL_HINT_IP/tinyfm/yaml.php
                http://$CTRL_HINT_IP/tinyfm/logrotor.php
- LuCI Views  : /usr/lib/lua/luci/view/{yaml.htm,logrotor.htm}
- LuCI Menu   : Services → OC D/E, Services → OC Ping (controller: toolsoc.lua)
- Web Log     : /www/oc-rotor.log (update tiap 1 menit; truncate tiap 5 menit)

Tips:
- Untuk pin manual: tambahkan --ref <sha|tag|branch>
- Ubah /etc/oc-rotor.env bila perlu, lalu:
  /etc/init.d/oc-rotor restart
- Cek log:
  logread -e oc-rotor | tail -n 50
EOF
