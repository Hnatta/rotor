#!/bin/sh
# installer.sh — Install Rotor dari rotor-main.zip (otomatis unduh, TIMPA semua, cleanup ZIP & folder)
# Pakai:
#   curl -fsSL https://raw.githubusercontent.com/Hnatta/rotor/main/installer.sh | sh
set -eu

ZIP_URL="https://github.com/Hnatta/rotor/archive/refs/heads/main.zip"
ZIP_PATH="/tmp/rotor-main.zip"
EXTRACT_DIR_GLOB="/tmp/rotor-*"

say(){ echo "[installer] $*"; }
die(){ echo "[installer][ERR] $*" >&2; exit 1; }

# ---------- cek root & platform ----------
[ "$(id -u)" = "0" ] || die "Harus dijalankan sebagai root"
[ -f /etc/openwrt_release ] || say "Peringatan: bukan OpenWrt (lanjut jika custom build)"

# ---------- paket minimal ----------
need_update=0
ensure_pkg(){
  # $1=binary, $2=pkg
  if ! command -v "$1" >/dev/null 2>&1; then
    [ $need_update -eq 0 ] && { opkg update || true; need_update=1; }
    opkg install "$2" || true
    command -v "$1" >/dev/null 2>&1 || die "Butuh '$1' (paket: $2)"
  fi
}

say "Memeriksa paket: curl, unzip, ca-bundle"
ensure_pkg curl curl
ensure_pkg unzip unzip
if [ ! -s /etc/ssl/certs/ca-certificates.crt ] && [ ! -s /etc/ssl/cert.pem ]; then
  [ $need_update -eq 0 ] && { opkg update || true; need_update=1; }
  opkg install ca-bundle || true
fi

# ---------- unduh ZIP ----------
say "Bersihkan sisa ekstrak lama (jika ada)"
rm -rf $EXTRACT_DIR_GLOB 2>/dev/null || true

say "Unduh ZIP: $ZIP_URL -> $ZIP_PATH"
curl -fSL --retry 3 --retry-delay 1 -H 'User-Agent: rotor-installer' \
  "$ZIP_URL" -o "$ZIP_PATH"

# ---------- ekstrak ZIP ----------
say "Ekstrak ZIP ke /tmp"
unzip -o -q "$ZIP_PATH" -d /tmp
ROOTDIR="$(find /tmp -maxdepth 1 -type d -name 'rotor-*' | head -n1 || true)"
[ -n "$ROOTDIR" ] || die "Folder hasil unzip tidak ditemukan (cari /tmp/rotor-*)"
say "Folder ekstrak: $ROOTDIR"

# ---------- helper salin (TIMPA) ----------
copy(){
  # $1=rel path dalam ZIP, $2=dst, $3(optional)=+x
  local rel="$1" dst="$2" mode="${3:-}" src
  src="${ROOTDIR}/${rel}"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"     # TIMPA selalu
    sed -i 's/\r$//' "$dst" 2>/dev/null || true
    [ "$mode" = "+x" ] && chmod +x "$dst"
    say "Pasang $rel -> $dst"
    return 0
  fi
  return 1
}

# ---------- pasang inti (TIMPA SEMUA) ----------
copy files/usr/bin/modem /usr/bin/modem +x || die "modem tidak ada dalam ZIP"
copy files/usr/bin/oc-rotor.sh /usr/bin/oc-rotor.sh +x || die "oc-rotor.sh tidak ada dalam ZIP"
copy files/etc/oc-rotor.env /etc/oc-rotor.env || true
[ -f /etc/oc-rotor.env ] && chmod 600 /etc/oc-rotor.env
copy files/etc/init.d/oc-rotor /etc/init.d/oc-rotor +x || die "init.d oc-rotor tidak ada dalam ZIP"

# ---------- TinyFM: HTML (utamakan), fallback stub bila tidak ada ----------
mkdir -p /www/tinyfm
# yaml.html
if ! copy files/www/tinyfm/yaml.html /www/tinyfm/yaml.html ; then
  say "yaml.html tidak ada di ZIP — membuat stub"
  cat > /www/tinyfm/yaml.html <<'EOF'
<!doctype html><meta charset="utf-8"><title>YAML Tool</title>
<style>body{font-family:sans-serif;margin:16px}textarea{width:100%;height:60vh}pre{white-space:pre-wrap;background:#f5f5f5;padding:8px}</style>
<h2>OC D/E (YAML)</h2>
<p>Stub halaman YAML. Ganti file ini di /www/tinyfm/yaml.html sesuai kebutuhan.</p>
EOF
fi
# logrotor.html
if ! copy files/www/tinyfm/logrotor.html /www/tinyfm/logrotor.html ; then
  say "logrotor.html tidak ada di ZIP — membuat stub viewer log"
  cat > /www/tinyfm/logrotor.html <<'EOF'
<!doctype html><meta charset="utf-8"><title>oc-rotor log</title>
<style>body{font-family:monospace;margin:10px}pre{white-space:pre-wrap}</style>
<pre id="log">Memuat /oc-rotor.log ...</pre>
<script>
async function load(){try{const r=await fetch('/oc-rotor.log',{cache:'no-store'});document.getElementById('log').textContent=await r.text();}catch(e){document.getElementById('log').textContent='Gagal baca /oc-rotor.log: '+e}}
load(); setInterval(load,5000);
</script>
EOF
fi
# bersihkan sisa PHP lama (jika ada)
rm -f /www/tinyfm/yaml.php /www/tinyfm/logrotor.php 2>/dev/null || true

# ---------- LuCI views & controller (TIMPA, stub bila tak ada) ----------
mkdir -p /usr/lib/lua/luci/view /usr/lib/lua/luci/controller
if ! copy files/usr/lib/lua/luci/view/yaml.htm /usr/lib/lua/luci/view/yaml.htm ; then
  say "yaml.htm tidak ada — membuat stub"
  cat > /usr/lib/lua/luci/view/yaml.htm <<'HTM'
<%+header%>
<h2>OC D/E (YAML)</h2>
<iframe src="/tinyfm/yaml.html" style="width:100%;height:80vh;border:0;"></iframe>
<%+footer%>
HTM
fi
if ! copy files/usr/lib/lua/luci/view/logrotor.htm /usr/lib/lua/luci/view/logrotor.htm ; then
  say "logrotor.htm tidak ada — membuat stub"
  cat > /usr/lib/lua/luci/view/logrotor.htm <<'HTM'
<%+header%>
<h2>OC Ping — Log</h2>
<iframe src="/tinyfm/logrotor.html" style="width:100%;height:80vh;border:0;"></iframe>
<%+footer%>
HTM
fi
if ! copy files/usr/lib/lua/luci/controller/toolsoc.lua /usr/lib/lua/luci/controller/toolsoc.lua ; then
  say "toolsoc.lua tidak ada — membuat stub controller"
  cat > /usr/lib/lua/luci/controller/toolsoc.lua <<'LUA'
module("luci.controller.toolsoc", package.seeall)
function index()
  entry({"admin","services","oc_de"},   template("yaml"),     _("OC D/E"),  20).dependent=false
  entry({"admin","services","oc_ping"}, template("logrotor"), _("OC Ping"), 21).dependent=false
end
LUA
fi

# ---------- bersihkan artefak lama yang bentrok ----------
rm -f /www/yaml.html /www/logrotor.html \
      /usr/lib/lua/luci/controller/oc-tools.lua \
      /usr/lib/lua/luci/controller/oc_tools.lua 2>/dev/null || true

# ---------- cron: enable + 2 entri ----------
if [ -x /etc/init.d/cron ]; then
  /etc/init.d/cron enable || true
  /etc/init.d/cron start  || true
fi
crontab -l 2>/dev/null > /tmp/mycron || true
sed -i '/oc-rotor\.log/d' /tmp/mycron 2>/dev/null || true
cat >> /tmp/mycron <<'CRON'
# Update file log untuk web tiap 1 menit (ambil 500 baris terakhir dari syslog yang memuat tag oc-rotor)
*/1 * * * *  /bin/sh -c 'logread -e oc-rotor | tail -n 500 > /www/oc-rotor.log'
# Bersihkan/truncate file log web tiap 5 menit
*/5 * * * *  /bin/sh -c ': > /www/oc-rotor.log'
CRON
crontab /tmp/mycron 2>/dev/null || true
rm -f /tmp/mycron

# ---------- enable services & reload web ----------
/etc/init.d/oc-rotor stop >/dev/null 2>&1 || true
/etc/init.d/oc-rotor enable
/etc/init.d/oc-rotor start || true
rm -f /tmp/luci-indexcache 2>/dev/null || true
[ -x /etc/init.d/uhttpd ] && (/etc/init.d/uhttpd reload 2>/dev/null || /etc/init.d/uhttpd restart 2>/dev/null || true)

# ---------- cleanup ZIP & folder ekstrak ----------
say "Hapus ZIP & folder ekstrak"
rm -f "$ZIP_PATH" 2>/dev/null || true
rm -rf "$ROOTDIR" 2>/dev/null || true

# ---------- ringkasan ----------
IP="$(uci get network.lan.ipaddr 2>/dev/null || echo 192.168.1.1)"
say "Selesai ✅"
cat <<EOF

== Ringkasan ==
- Modem CLI   : /usr/bin/modem
- Rotor       : /usr/bin/oc-rotor.sh (service: /etc/init.d/oc-rotor)
- Env         : /etc/oc-rotor.env  [perm 600]
- Web (HTML)  : http://$IP/tinyfm/yaml.html
                http://$IP/tinyfm/logrotor.html
- LuCI Views  : /usr/lib/lua/luci/view/{yaml.htm,logrotor.htm}
- LuCI Menu   : Services → OC D/E, Services → OC Ping (controller: toolsoc.lua)
- Web Log     : /www/oc-rotor.log (update tiap 1 menit; truncate tiap 5 menit)

(Berkas /tmp/rotor-main.zip & folder ekstrak sudah dihapus.)
EOF
