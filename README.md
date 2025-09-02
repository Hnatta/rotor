# rotor
Menganalisa Ping Openclash dan Membuat keputusan untuk modem b310s AIO

**  Satu perintah install (di OpenWrt)  **

```bash
curl -fsSL https://raw.githubusercontent.com/Hnatta/rotor/main/installer.sh | sh
```
  
# langsung eksekusi cek & finalisasi di bawah ini (sekali paste).

```bash
# 1) Cek apakah semua file penting sudah ada
for p in \
  /usr/bin/modem \
  /usr/bin/oc-rotor.sh \
  /etc/oc-rotor.env \
  /etc/init.d/oc-rotor \
  /www/yaml.html \
  /www/logrotor.html \
  /usr/lib/lua/luci/controller/toolsoc.lua
do [ -e "$p" ] && echo "OK  $p" || echo "MISSING $p"; done

# 2) Kalau ada yang "MISSING", ambil yang kurang saja (aman di-run meski sudah ada)
BASE="https://raw.githubusercontent.com/Hnatta/rotor/main"
curl -fsSL "$BASE/files/etc/init.d/oc-rotor" -o /etc/init.d/oc-rotor && chmod +x /etc/init.d/oc-rotor
curl -fsSL "$BASE/files/www/yaml.html" -o /www/yaml.html
curl -fsSL "$BASE/files/www/logrotor.html" -o /www/logrotor.html
curl -fsSL "$BASE/files/usr/lib/lua/luci/controller/toolsoc.lua" -o /usr/lib/lua/luci/controller/toolsoc.lua

# 3) Pastikan permission executable untuk bin & service
chmod +x /usr/bin/modem /usr/bin/oc-rotor.sh /etc/init.d/oc-rotor

# 4) (Opsional) Sesuaikan env kalau perlu, lalu start service
#    Edit manual jika perlu: vi /etc/oc-rotor.env
#    Minimal pastikan:
#    CTRL="http://127.0.0.1:9090"
#    SECRET="12345"
#    GROUPS="SGR_ACTIVE IDN_ACTIVE WRD_ACTIVE"
#    PING_URL="http://www.gstatic.com/generate_204"

# Apply & jalankan
/etc/init.d/oc-rotor enable
/etc/init.d/oc-rotor restart

# 5) Reload LuCI/uHTTPd & bersihkan cache menu
rm -f /tmp/luci-indexcache
/etc/init.d/uhttpd reload 2>/dev/null || /etc/init.d/uhttpd restart 2>/dev/null || true

# 6) Cek log rotor
logread -e oc-rotor | tail -n 50
```
# Tambahkan ke cronjob

```bash

/etc/init.d/cron enable
/etc/init.d/cron start

crontab -l > /tmp/mycron 2>/dev/null
cat >> /tmp/mycron <<'CRON'
# Update file log untuk web tiap 1 menit (ambil 500 baris terakhir dari syslog yang memuat tag oc-rotor)
*/1 * * * *  /bin/sh -c 'logread -e oc-rotor | tail -n 500 > /www/oc-rotor.log'
# Bersihkan/truncate file log web tiap 5 menit
*/5 * * * *  /bin/sh -c ': > /www/oc-rotor.log'
CRON
crontab /tmp/mycron
rm -f /tmp/mycron
```
# Begitu selesai, buka LuCI → Services → OC D/E dan OC Ping, atau langsung akses:

** http://192.168.1.1/oc-yaml.html

** http://192.168.1.1/rotor-log.html
