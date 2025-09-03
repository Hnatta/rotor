cat > /tmp/install-rotor-from-zip.sh <<'SH'
#!/bin/sh
set -eu

ZIP="/tmp/rotor-main.zip"

say(){ echo "[zip-installer] $*"; }
die(){ echo "[zip-installer][ERR] $*" >&2; exit 1; }

[ -f "$ZIP" ] || die "ZIP tidak ditemukan: $ZIP (taruh di /tmp dulu)"

# --- kebutuhan dasar ---
need_update=0
ensure() {
  bin="$1"; pkg="$2"
  if ! command -v "$bin" >/dev/null 2>&1; then
    [ $need_update -eq 0 ] && { opkg update || true; need_update=1; }
    opkg install "$pkg" || true
    command -v "$bin" >/dev/null 2>&1 || die "Butuh $bin (paket: $pkg)"
  fi
}
ensure unzip unzip
ensure curl curl
# CA untuk TLS (kalau nanti pakai curl/wget lain)
if [ ! -s /etc/ssl/certs/ca-certificates.crt ] && [ ! -s /etc/ssl/cert.pem ]; then
  [ $need_update -eq 0 ] && { opkg update || true; need_update=1; }
  opkg install ca-bundle || true
fi

# --- ekstrak ZIP ---
say "Ekstrak ZIP..."
rm -rf /tmp/rotor-main /tmp/rotor-* 2>/dev/null || true
unzip -o -q "$ZIP" -d /tmp
ROOTDIR="$(find /tmp -maxdepth 1 -type d -name 'rotor-*' | head -n1 || true)"
[ -n "$ROOTDIR" ] || die "Folder hasil unzip tidak ditemukan (cari rotor-*)"

copy() { # $1=relpath dlm ZIP, $2=dst, $3(optional)=+x
  rel="$1"; dst="$2"; mode="${3:-}"
  src="${ROOTDIR}/${rel}"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    sed -i 's/\r$//' "$dst" 2>/dev/null || true
    [ "$mode" = "+x" ] && chmod +x "$dst"
    say "Pasang $rel -> $dst"
    return 0
  fi
  return 1
}

# --- pasang inti (TIMPA) ---
copy files/usr/bin/modem /usr/bin/modem +x
copy files/usr/bin/oc-rotor.sh /usr/bin/oc-rotor.sh +x
copy files/etc/oc-rotor.env /etc/oc-rotor.env || true
[ -f /etc/oc-rotor.env ] && chmod 600 /etc/oc-rotor.env
copy files/etc/init.d/oc-rotor /etc/init.d/oc-rotor +x

# --- TinyFM: utamakan HTML; kalau tidak ada, pakai PHP; terakhir buat stub HTML ---
# YAML viewer
if ! copy files/www/tinyfm/yaml.html /www/tinyfm/yaml.html ; then
  copy files/www/tinyfm/yaml.php /www/tinyfm/yaml.php || true
fi
# Log viewer
if ! copy files/www/tinyfm/logrotor.html /www/tinyfm/logrotor.html ; then
  if ! copy files/www/tinyfm/logrotor.php /www/tinyfm/logrotor.php ; then
    mkdir -p /www/tinyfm
    cat > /www/tinyfm/logrotor.html <<'EOF'
<!doctype html><meta charset="utf-8"><title>oc-rotor log</title>
<pre id="log" style="white-space:pre-wrap"></pre>
<script>
async function load(){try{const r=await fetch('/oc-rotor.log',{cache:'no-store'});document.getElementById('log').textContent=await r.text();}catch(e){document.getElementById('log').textContent='Gagal baca /oc-rotor.log: '+e}}
load(); setInterval(load,5000);
</script>
EOF
  fi
fi

# --- LuCI views & controller ---
copy files/usr/lib/lua/luci/view/yaml.htm /usr/lib/lua/luci/view/yaml.htm || true
copy files/usr/lib/lua/luci/view/logrotor.htm /usr/lib/lua/luci/view/logrotor.htm || true
copy files/usr/lib/lua/luci/controller/toolsoc.lua /usr/lib/lua/luci/controller/toolsoc.lua || true

# --- bersihkan artefak lama yang bentrok ---
rm -f /www/yaml.html /www/logrotor.html \
      /usr/lib/lua/luci/controller/oc-tools.lua \
      /usr/lib/lua/luci/controller/oc_tools.lua 2>/dev/null || true

# --- cron: enable + jadwalkan 2 entri ---
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

# --- nyalakan service & reload web ---
/etc/init.d/oc-rotor stop >/dev/null 2>&1 || true
/etc/init.d/oc-rotor enable
/etc/init.d/oc-rotor start

rm -f /tmp/luci-indexcache 2>/dev/null || true
[ -x /etc/init.d/uhttpd ] && (/etc/init.d/uhttpd reload 2>/dev/null || /etc/init.d/uhttpd restart 2>/dev/null || true)

say "Selesai. Coba akses:"
IP="$(uci get network.lan.ipaddr 2>/dev/null || echo 192.168.1.1)"
echo " - http://$IP/tinyfm/yaml.html  (atau .php jika itu yang terpasang)"
echo " - http://$IP/tinyfm/logrotor.html (atau .php jika itu yang terpasang)"
echo "Log web: /www/oc-rotor.log (diputar tiap menit oleh cron)"
SH

chmod +x /tmp/install-rotor-from-zip.sh
sh /tmp/install-rotor-from-zip.sh
