<!doctype html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Converter Link → YAML (Trojan / VLESS / VMess / SS / WireGuard)</title>
  <style>
    :root{
      --bg:#0b0f14; --panel:#11161d; --panel2:#0f141a;
      --text:#e8eef6; --muted:#96a2b4; --accent:#6ce5b1;
      --border:#1e2630; --ring:#253242; --shadow:0 10px 30px rgba(0,0,0,.35);
      --radius:16px;
    }
    @media (prefers-color-scheme:light){
      :root{ --bg:#f6f8fb; --panel:#fff; --panel2:#fff; --text:#0b1220; --muted:#5b6676; --accent:#17a673; --border:#e6eaf1; --ring:#dfe7f3; }
    }
    *{ box-sizing:border-box }
    body{
      margin:0; min-height:100vh; color:var(--text);
      background: radial-gradient(1000px 700px at 10% -10%, #172130 0%, transparent 60%),
                  radial-gradient(1000px 700px at 110% 10%, #172130 0%, transparent 60%),
                  var(--bg);
      font:15px/1.55 ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, "Helvetica Neue", Arial, "Noto Sans";
      padding:24px;
    }
    .wrap{ max-width:1100px; margin:0 auto; display:grid; gap:16px; grid-template-columns:1fr 1fr; }
    @media (max-width:860px){ .wrap{ grid-template-columns:1fr; } }
    .card{ background:linear-gradient(180deg, var(--panel), var(--panel2)); border:1px solid var(--border); border-radius:var(--radius); box-shadow:var(--shadow); padding:16px; }
    .head{ display:flex; align-items:center; justify-content:space-between; gap:12px; margin-bottom:10px; }
    .title{ font-weight:800; letter-spacing:.2px }
    .sub{ color:var(--muted); font-size:12px }
    .btns{ display:flex; gap:8px; flex-wrap:wrap }
    button{ appearance:none; border:1px solid var(--border); background:#0f141a; color:var(--text); padding:8px 12px; border-radius:12px; cursor:pointer; transition:transform .05s, background .2s, border-color .2s }
    button:hover{ background:#0c1117; border-color:var(--ring) }
    button:active{ transform:translateY(1px) }
    .btn-ghost{ background:transparent }
    .btn-accent{ background:var(--accent); color:#0b0f14; border-color:transparent }
    .btn-accent:hover{ filter:brightness(.95) }
    textarea, pre{
      width:100%; border:1px solid var(--border); background:#0c1117; color:var(--text);
      border-radius:12px; padding:12px; resize:vertical; min-height:230px;
      font-family:ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace; font-size:13px; line-height:1.6; tab-size:2; outline:none;
    }
    textarea:focus, pre:focus{ border-color:var(--ring); box-shadow:0 0 0 4px color-mix(in oklab, var(--ring) 40%, transparent) }
    pre{ margin:0; white-space:pre; overflow:auto }
    .note{ margin-top:6px; font-size:12px; color:#f3b45d }
    .note[hidden]{ display:none }
    .foot{ display:flex; justify-content:space-between; align-items:center; gap:8px; margin-top:8px }
    .hint{ font-size:12px; color:var(--muted) }
  </style>
</head>
<body>
  <div class="warp"></div>
<script>
(() => {
  const root = document.querySelector('.warp') || (() => {
    const el = document.createElement('div');
    el.className = 'warp';
    document.body.appendChild(el);
    return el;
  })();

  const html = `
  <div class="wrap">
    <!-- KIRI: Converter -->
    <section class="card" aria-label="Converter">
      <div class="head">
        <div>
          <div class="title">Converter @h_natta v.2</div>
          <div class="sub">Tempel banyak link (satu per baris): <b>trojan://</b>, <b>vless://</b>, <b>vmess://</b>, <b>ss://</b>, <b>wireguard://</b>/<b>wg://</b></div>
        </div>
        <div class="btns">
          <button id="pasteBtn" title="Paste dari clipboard">Paste</button>
          <button id="clearBtn" class="btn-ghost" title="Bersihkan input">Bersihkan</button>
        </div>
      </div>
      <textarea id="input" placeholder="Contoh:
trojan://password@host:443?type=ws&host=cdn.example.com&path=%2Fws&sni=example.com#Nama
vless://uuid@host:443?type=grpc&security=tls&serviceName=gun&sni=example.com#Nama
vmess://xxxxx
ss://xxxx
wireguard://xxxxx"></textarea>
      <div id="pasteNote" class="note" hidden></div>
      <div class="foot"><span class="hint">Hasil otomatis muncul saat input berubah.</span></div>
    </section>
    <section class="card" aria-label="Hasil">
      <div class="head">
        <div>
          <div class="title">Hasil (YAML)</div>
          <div class="sub">Format list: <code>- name: ...</code> (multi akun → banyak item)</div>
        </div>
        <div class="btns">
          <button id="copyBtn" class="btn-accent" title="Salin YAML">Salin</button>
        </div>
      </div>
      <pre id="out" tabindex="0" aria-label="Output YAML"></pre>
      <div class="foot"><span class="hint">Dukungan: Trojan/VLESS/VMess (+WS/gRPC/SNI/CDN/XTLS), Shadowsocks (+plugin), WireGuard.</span></div>
    </section>
  </div>`;
  root.innerHTML = html;
  const $ = (sel) => root.querySelector(sel);
  const input = $('#input');
  const out = $('#out');
  const pasteBtn = $('#pasteBtn');
  const clearBtn = $('#clearBtn');
  const copyBtn = $('#copyBtn');
  const pasteNote = $('#pasteNote');
  const q = (s) => JSON.stringify(String(s ?? ''));
  function convertToYaml(text) {
    const lines = String(text || '')
      .split(/\r?\n/)
      .map(l => l.trim())
      .filter(Boolean);

    if (!lines.length) return '';

    let i = 0;
    const items = lines.map(line => {
      i++;
      const hash = line.indexOf('#');
      let name = hash >= 0 ? line.slice(hash + 1) : `Link ${i}`;
      try {
        name = decodeURIComponent(name.replace(/\+/g, ' '));
      } catch (_) {}
      if (name.length > 120) name = name.slice(0, 117) + '...';
      return `- name: ${q(name)}\n  uri: ${q(line)}`;
    });

    return items.join('\n');
  }

  function syncOutput() {
    out.textContent = convertToYaml(input.value);
  }
  async function safeReadClipboard() {
    if (!window.isSecureContext) throw new Error('Clipboard API butuh HTTPS/localhost');
    if (!navigator.clipboard?.readText) throw new Error('Browser tidak mendukung navigator.clipboard.readText');
    return await navigator.clipboard.readText();
  }

  async function safeWriteClipboard(text) {
    if (navigator.clipboard?.writeText) {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch (e) {}
    }
    try {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.top = '-9999px';
      document.body.appendChild(ta);
      ta.focus();
      ta.select();
      const ok = document.execCommand('copy');
      document.body.removeChild(ta);
      return ok;
    } catch (_) {
      return false;
    }
  }
  input.addEventListener('input', syncOutput);

  clearBtn?.addEventListener('click', () => {
    input.value = '';
    syncOutput();
    input.focus();
  });

  copyBtn?.addEventListener('click', async () => {
    const ok = await safeWriteClipboard(out.textContent || '');
    if (!ok) {
      const sel = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(out);
      sel.removeAllRanges();
      sel.addRange(range);
      alert('Gagal menyalin otomatis. Silakan tekan Ctrl/Cmd+C.');
    } else {
      copyBtn.disabled = true;
      const prev = copyBtn.textContent;
      copyBtn.textContent = 'Tersalin!';
      setTimeout(() => { copyBtn.textContent = prev; copyBtn.disabled = false; }, 900);
    }
  });

  pasteBtn?.addEventListener('click', async () => {
    try {
      const text = await safeReadClipboard();
      if (!text) throw new Error('Clipboard kosong');
      input.value = text;
      syncOutput();
      pasteNote.hidden = true;
    } catch (err) {
      pasteNote.hidden = false;
      pasteNote.textContent = 'Tidak bisa membaca clipboard otomatis. Tekan Ctrl/Cmd+V di kotak yang muncul…';

      const fallback = document.createElement('div');
      fallback.setAttribute('role', 'textbox');
      fallback.contentEditable = 'true';
      fallback.style.cssText =
        'position:fixed;left:16px;bottom:16px;right:16px;min-height:80px;padding:10px;border:1px dashed #888;background:#fff;z-index:9999;';
      fallback.textContent = 'Tempel (Ctrl/Cmd + V) di sini…';
      document.body.appendChild(fallback);
      fallback.focus();

      const onPaste = (e) => {
        const t = (e.clipboardData || window.clipboardData).getData('text');
        e.preventDefault();
        input.value = t;
        syncOutput();
        cleanup();
      };
      const onBlur = () => setTimeout(cleanup, 100);

      function cleanup() {
        pasteNote.hidden = true;
        fallback.removeEventListener('paste', onPaste);
        fallback.removeEventListener('blur', onBlur);
        if (fallback.parentNode) fallback.parentNode.removeChild(fallback);
        input.focus();
      }

      fallback.addEventListener('paste', onPaste, { once: true });
      fallback.addEventListener('blur', onBlur);
    }
  });
  syncOutput();
})();

  const $ = sel => document.querySelector(sel);
  const input = $('#input'), out = $('#out');
  const pasteBtn = $('#pasteBtn'), clearBtn = $('#clearBtn'), copyBtn = $('#copyBtn');
  const pasteNote = $('#pasteNote');

  const safeDecode = s => { try{ return decodeURIComponent(s); } catch { return s; } };
  const b64fix = s => {
    s = String(s||'').replace(/-/g,'+').replace(/_/g,'/').replace(/\s+/g,'').trim();
    const pad = s.length % 4; return pad ? s + '='.repeat(4-pad) : s;
  };
  const tryJSON = s => { try{ return JSON.parse(s); }catch{ return null; } };
  const isPlain = v => typeof v==='string'||typeof v==='number'||typeof v==='boolean'||v===null;
  function fmtScalar(v){
    if (typeof v==='string' && (/:|#|\n/.test(v) || /^\s|\s$|^$/.test(v))) return '"' + v.replace(/"/g,'\\"') + '"';
    return v;
  }
  function toYAMLObject(obj, indent=0){
    const sp = '  '.repeat(indent);
    const lines = [];
    for (const [k,vRaw] of Object.entries(obj)){
      if (vRaw===undefined || vRaw==='' || (typeof vRaw==='object' && vRaw && !Array.isArray(vRaw) && Object.keys(vRaw).length===0)) continue;
      if (isPlain(vRaw)){
        lines.push(`${sp}${k}: ${fmtScalar(vRaw)}`);
      } else if (Array.isArray(vRaw)){
        if (!vRaw.length) continue;
        lines.push(`${sp}${k}:`);
        for (const item of vRaw){
          if (isPlain(item)) lines.push(`${sp}  - ${fmtScalar(item)}`);
          else { lines.push(`${sp}  -`); lines.push(toYAMLObject(item, indent+2)); }
        }
      } else {
        lines.push(`${sp}${k}:`);
        lines.push(toYAMLObject(vRaw, indent+1));
      }
    }
    return lines.join('\n');
  }
  function toYAMLListOfMaps(arr){
    const lines = [];
    for (const obj of arr){
      const entries = Object.entries(obj).filter(([k,v])=>{
        if (v===undefined || v==='') return false;
        if (typeof v==='object' && v && !Array.isArray(v) && Object.keys(v).length===0) return false;
        return true;
      });
      if (!entries.length){ lines.push('- {}'); continue; }
      const [k0,v0] = entries[0];
      if (isPlain(v0)){
        lines.push(`- ${k0}: ${fmtScalar(v0)}`);
      } else if (Array.isArray(v0)){
        lines.push(`- ${k0}:`); for (const item of v0){ isPlain(item)? lines.push(`  - ${fmtScalar(item)}`) : (lines.push('  -'), lines.push(toYAMLObject(item,2))); }
      } else {
        lines.push(`- ${k0}:`); lines.push(toYAMLObject(v0,1));
      }
      for (let i=1;i<entries.length;i++){
        const [k,v] = entries[i];
        if (isPlain(v)) lines.push(`  ${k}: ${fmtScalar(v)}`);
        else if (Array.isArray(v)){
          if (!v.length) continue;
          lines.push(`  ${k}:`);
          for (const item of v){ isPlain(item) ? lines.push(`    - ${fmtScalar(item)}`) : (lines.push('    -'), lines.push(toYAMLObject(item,3))); }
        } else {
          lines.push(`  ${k}:`); lines.push(toYAMLObject(v,2));
        }
      }
    }
    return lines.join('\n');
  }

  function commonNameFromURL(url){
    const tag = safeDecode(url.hash?.slice(1) || '');
    return tag || url.hostname || 'proxy';
  }
  function commonNet(q){
    const t = (q.get('type') || q.get('transport') || '').toLowerCase();
    if (['ws','grpc','tcp','h2','http'].includes(t)) return t==='http' ? 'h2' : t;
    return '';
  }
  function grabSNI(url,q){ return q.get('sni') || q.get('servername') || q.get('serverName') || q.get('host') || url.hostname || ''; }
  const yes = v => ['1','true','tls','reality','xtls'].includes(String(v||'').toLowerCase());

  function wsOpts(q){
    const path = safeDecode(q.get('path') || '/');
    const host = q.get('host') || q.get('hostHeader') || '';
    const headers = {}; if (host) headers['Host'] = host;
    return { path, headers };
  }
  function grpcOpts(q){
    const serviceName = q.get('serviceName') || q.get('grpcServiceName') || 'gun';
    return { 'grpc-service-name': serviceName };
  }
  function baseProfile({name, server, port, type, sni, tls, network, skipCert=true}){
    const base = { name, server, port, type, 'skip-cert-verify': !!skipCert, udp: true };
    if (sni) base['sni'] = sni;
    if (tls !== undefined) base['tls'] = !!tls;
    if (network) base['network'] = network;
    return base;
  }
  function buildFromTrojan(url){
    const q = url.searchParams;
    const name = commonNameFromURL(url), server = url.hostname, port = Number(url.port || 443);
    const password = decodeURIComponent(url.username || ''); if (!password) throw new Error('Trojan: password kosong.');
    const network = commonNet(q), sni = grabSNI(url,q);
    const prof = baseProfile({ name, server, port, type:'trojan', sni, tls: undefined, network });
    prof.password = password;
    if (network==='ws') prof['ws-opts'] = wsOpts(q);
    if (network==='grpc') prof['grpc-opts'] = grpcOpts(q);
    return prof;
  }
  function buildFromVLESS(url){
    const q = url.searchParams;
    const name = commonNameFromURL(url), server = url.hostname, port = Number(url.port || 443);
    const uuid = decodeURIComponent(url.username || ''); if (!uuid) throw new Error('VLESS: UUID kosong.');
    const network = commonNet(q), tls = yes(q.get('security')) || yes(q.get('tls')), sni = grabSNI(url,q);
    const flow = q.get('flow') || '';
    const prof = baseProfile({ name, server, port, type:'vless', sni, tls, network });
    prof.uuid = uuid; if (flow) prof.flow = flow;
    if (network==='ws') prof['ws-opts'] = wsOpts(q);
    if (network==='grpc') prof['grpc-opts'] = grpcOpts(q);
    return prof;
  }
  function buildFromVMessURL(url){
    const q = url.searchParams;
    const name = commonNameFromURL(url), server = url.hostname, port = Number(url.port || 443);
    const uuid = decodeURIComponent(url.username || ''); if (!uuid) throw new Error('VMess: UUID kosong.');
    const network = commonNet(q), tls = yes(q.get('security')) || yes(q.get('tls')), sni = grabSNI(url,q);
    const aid = Number(q.get('aid') || q.get('alterId') || 0), cipher = q.get('scy') || 'auto';
    const prof = baseProfile({ name, server, port, type:'vmess', sni, tls, network });
    prof.uuid = uuid; prof.alterId = aid; prof.cipher = cipher;
    if (network==='ws') prof['ws-opts'] = wsOpts(q);
    if (network==='grpc') prof['grpc-opts'] = grpcOpts(q);
    return prof;
  }
  function buildFromVMessJSON(j){
    const name = j.ps || j.name || j.sni || j.add || 'vmess';
    const server = j.add || j.server || ''; const port = Number(j.port || 443);
    const uuid = j.id || j.uuid || ''; if (!uuid || !server) throw new Error('VMess: JSON tidak lengkap.');
    const network = (j.net || j.type || '').toLowerCase(), tls = yes(j.tls);
    const sni = j.sni || j.servername || j.host || server;
    const aid = Number(j.aid || j.alterId || 0), cipher = j.scy || j.cipher || 'auto';
    const prof = baseProfile({ name, server, port, type:'vmess', sni, tls, network });
    prof.uuid = uuid; prof.alterId = aid; prof.cipher = cipher;
    if (network==='ws'){
      const headers = {}; if (j.host) headers['Host'] = j.host;
      prof['ws-opts'] = { path: j.path || '/', headers };
    }
    if (network==='grpc'){
      prof['grpc-opts'] = { 'grpc-service-name': j.path || j.serviceName || 'gun' };
    }
    return prof;
  }
  function buildFromSS(raw){
    const m = /^ss:\/\/([^#?\s]+)(?:\?([^#\s]+))?(?:#(.+))?$/i.exec(raw.trim());
    if (!m) throw new Error('SS: format tidak valid.');
    const core = m[1], qs = m[2] || '', tag = m[3] ? safeDecode(m[3]) : '';
    let method='', password='', server='', port='';

    if (core.includes('@') && core.includes(':')){
      let url; try{ url = new URL(raw); }catch{ throw new Error('SS URL tidak valid.'); }
      method = decodeURIComponent(url.username || ''); password = decodeURIComponent(url.password || '');
      server = url.hostname; port = url.port;
    } else {
      const decoded = atob(b64fix(core));
      const atIdx = decoded.lastIndexOf('@'); if (atIdx === -1) throw new Error('SS: base64 tidak mengandung "@".');
      const cred = decoded.slice(0, atIdx); const hostport = decoded.slice(atIdx+1);
      const colon = cred.indexOf(':'); if (colon === -1) throw new Error('SS: base64 perlu "method:password".');
      method = cred.slice(0, colon); password = cred.slice(colon+1);
      const hp = /^(.+):(\d+)$/.exec(hostport.trim()); if (!hp) throw new Error('SS: host:port tidak valid.');
      server = hp[1]; port = hp[2];
    }

    const q = new URLSearchParams(qs);
    const pluginRaw = q.get('plugin') ? safeDecode(q.get('plugin')) : '';
    let plugin='', pluginOpts={};
    if (pluginRaw){
      const [pname, ...rest] = pluginRaw.split(';').filter(Boolean);
      const opts = {};
      for (const seg of rest){
        if (!seg.includes('=')) { opts[seg.toLowerCase()] = true; continue; }
        const [k,v] = seg.split('=');
        opts[k.trim()] = safeDecode((v||'').trim());
      }
      if (/v2ray-plugin/i.test(pname)){
        plugin = 'v2ray-plugin';
        const mode = (opts.mode || (opts.grpc ? 'grpc' : 'websocket')).toString();
        pluginOpts = { mode };
        if (opts.tls) pluginOpts.tls = true;
        if (opts.host || opts.servername) pluginOpts.host = opts.host || opts.servername;
        if (opts.path) pluginOpts.path = opts.path.startsWith('/') ? opts.path : '/' + opts.path;
        if (mode === 'grpc' && (opts.serviceName || opts['serviceName'])) pluginOpts['grpc-service-name'] = opts.serviceName || opts['serviceName'];
      } else if (/obfs-local|simple-obfs/i.test(pname)){
        plugin = 'obfs'; pluginOpts = { mode: (opts.obfs || opts.mode || 'tls').toString(), host: opts['obfs-host'] || opts.host || '' };
      } else { plugin = pname; if (rest.length) pluginOpts = { raw: rest.join(';') }; }
    }

    const name = tag || server;
    const prof = { name, server, port:Number(port), type:'ss', cipher:method, password, udp:true };
    if (plugin) prof['plugin'] = plugin;
    if (plugin && Object.keys(pluginOpts).length) prof['plugin-opts'] = pluginOpts;
    return prof;
  }
  function wgFromJSON(j){
    const name = j.name || j.ps || j.tag || j.server || 'wireguard';
    const server = j.server || j.host || j.address || '';
    const port = Number(j.port || j.server_port || 51820);
    const privateKey = j.private_key || j.privateKey || j.privkey || '';
    const publicKey  = j.public_key  || j.publicKey  || j.serverPublicKey || j.peerPublicKey || '';
    const psk = j.preshared_key || j.presharedKey || j.psk || '';
    const addresses = (j.addresses || j.address || j.ip || '').toString();
    const dns = j.dns || j.dns_servers || '';

    const prof = { name, server, port, type:'wireguard', 'private-key': privateKey, 'public-key': publicKey, udp:true };
    if (psk) prof['pre-shared-key'] = psk;
    const addrs = (Array.isArray(addresses)? addresses : addresses.split(',')).map(s=>String(s||'').trim()).filter(Boolean);
    for (const a of addrs){ if (a.includes(':')) prof['ipv6'] = a; else prof['ip'] = a; }
    if (dns){
      const arr = Array.isArray(dns) ? dns : String(dns).split(/[,\s]+/).filter(Boolean);
      prof['dns'] = arr.length>1 ? arr : arr[0];
    }
    if (j.mtu) prof['mtu'] = Number(j.mtu);
    if (j.keepalive || j.persistent_keepalive) prof['keepalive'] = Number(j.keepalive || j.persistent_keepalive);
    if (j.reserved && Array.isArray(j.reserved)) prof['reserved'] = j.reserved.slice(0,3).map(Number);
    return prof;
  }
  function buildFromWireGuard(raw){
    const trimmed = raw.trim();
    const rest = trimmed.replace(/^[a-z]+:\/\//i,'');
    const maybeJSON = tryJSON(safeDecode(atob(b64fix(rest))));
    if (maybeJSON) return wgFromJSON(maybeJSON);
    let url; try{ url = new URL(trimmed); } catch { throw new Error('WireGuard: format tidak dikenali.'); }
    const q = url.searchParams;
    const name = safeDecode(url.hash?.slice(1) || '') || url.hostname || 'wireguard';
    const server = url.hostname; const port = Number(url.port || 51820);
    const privateKey = q.get('privateKey') || q.get('private_key') || q.get('privkey') || '';
    const publicKey  = q.get('publicKey') || q.get('public_key') || q.get('serverPublicKey') || q.get('peerPublicKey') || '';
    const psk = q.get('presharedKey') || q.get('psk') || q.get('preSharedKey') || '';
    const address = q.get('address') || q.get('addresses') || ''; const dns = q.get('dns') || '';
    const mtu = q.get('mtu') || ''; const keepalive = q.get('keepalive') || q.get('persistentKeepalive') || '';
    const reserved = q.get('reserved') || '';

    const prof = { name, server, port, type:'wireguard', 'private-key': privateKey, 'public-key': publicKey, udp:true };
    if (psk) prof['pre-shared-key'] = psk;
    const addrs = address.split(',').map(s=>s.trim()).filter(Boolean);
    for (const a of addrs){ if (a.includes(':')) prof['ipv6'] = a; else prof['ip'] = a; }
    if (dns){ const list = dns.split(/[,\s]+/).filter(Boolean); prof['dns'] = list.length>1 ? list : list[0]; }
    if (mtu) prof['mtu'] = Number(mtu);
    if (keepalive) prof['keepalive'] = Number(keepalive);
    if (reserved){
      const parts = reserved.split(/[,\s]+/).filter(Boolean).map(x=>{
        if (/^0x/i.test(x)) return parseInt(x,16);
        if (/^[0-9a-f]{2}$/i.test(x)) return parseInt(x,16);
        const n = parseInt(x,10); return isNaN(n)?undefined:n;
      }).filter(v=>v!==undefined);
      if (parts.length) prof['reserved'] = parts.slice(0,3);
    }
    return prof;
  }
  function parseSingleLink(raw){
    const s = raw.trim(); if (!s) throw new Error('Link kosong.');
    if (/^vmess:\/\//i.test(s) && !s.includes('@')){
      const b64 = s.replace(/^vmess:\/\//i,''); const json = tryJSON(atob(b64fix(b64)));
      if (!json) throw new Error('VMess base64 tidak valid.'); return buildFromVMessJSON(json);
    }
    if (/^ss:\/\//i.test(s) || /^shadowsocks:\/\//i.test(s)) return buildFromSS(s.replace(/^shadowsocks:\/\//i,'ss://'));
    if (/^(wireguard|wg):\/\//i.test(s)) return buildFromWireGuard(s);
    let url; try{ url = new URL(s); } catch{ throw new Error('URL tidak valid.'); }
    const scheme = url.protocol.replace(':','').toLowerCase();
    if (!['trojan','vless','vmess'].includes(scheme)) throw new Error('Skema tidak didukung.');
    if (scheme==='vmess' && url.username && url.host) return buildFromVMessURL(url);
    if (scheme==='trojan') return buildFromTrojan(url);
    if (scheme==='vless')  return buildFromVLESS(url);
    throw new Error('Format tidak dikenali.');
  }

  function parseAll(raw){
    const lines = raw.split(/\r?\n/).map(s=>s.trim()).filter(Boolean);
    let profiles=[], errors=[];
    for (let i=0;i<lines.length;i++){
      const line = lines[i];
      try{ profiles.push(parseSingleLink(line)); }
      catch(e){ errors.push({index:i+1, reason:e.message}); }
    }
    if (!profiles.length && !errors.length){
      // fallback: split by whitespace
      const parts = raw.split(/\s+/).map(s=>s.trim()).filter(Boolean);
      for (let i=0;i<parts.length;i++){
        const t = parts[i];
        if (!/^(trojan|vless|vmess|ss|shadowsocks|wireguard|wg):\/\//i.test(t)) continue;
        try{ profiles.push(parseSingleLink(t)); }catch(e){ errors.push({index:i+1, reason:e.message}); }
      }
    }
    return {profiles, errors};
  }
  function render(){
    const val = input.value;
    if (!val.trim()){ out.textContent=''; return; }
    const {profiles, errors} = parseAll(val);
    if (profiles.length){ out.textContent = toYAMLListOfMaps(profiles); }
    else { out.textContent = ''; }
    // (Opsional) tampilkan error pertama di note jika ingin:
    if (errors.length && !pasteNote.hidden){
      // biarkan note untuk pesan paste; tidak diubah di sini
    }
  }
  pasteBtn.addEventListener('click', async () => {
    pasteNote.hidden = true; pasteNote.textContent = '';
    if (!navigator.clipboard || !navigator.clipboard.readText){
      pasteNote.hidden = false;
      pasteNote.textContent = 'Browser tidak mendukung API clipboard. Gunakan Ctrl/Cmd+V.';
      return;
    }
    try {
      const text = await navigator.clipboard.readText();
      input.value = text;  // sesuai preferensi Anda: tanpa trim
      render();
    } catch (e) {
      pasteNote.hidden = false;
      pasteNote.textContent = 'Gagal mengakses clipboard. Izinkan akses atau gunakan Ctrl/Cmd+V.';
    }
  });
  clearBtn.addEventListener('click', () => { input.value = ''; render(); input.focus(); });
  copyBtn.addEventListener('click', async () => {
    const text = (out?.textContent || '').trim();
    if (!text) return;
    try{
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text);
      } else {
        const ta = document.createElement('textarea');
        ta.value = text; ta.setAttribute('readonly',''); ta.style.position='fixed'; ta.style.opacity='0';
        document.body.appendChild(ta); ta.select(); document.execCommand('copy'); document.body.removeChild(ta);
      }
      const old = copyBtn.textContent; copyBtn.textContent = 'Disalin ✓';
      setTimeout(()=> copyBtn.textContent = old, 1200);
    }catch(e){ /* diamkan seperti gaya Anda */ }
  });
  input.addEventListener('input', render);
  setTimeout(()=> input.focus(), 50);
  
  /* ====== Smart paste: insert di kursor + tambah newline & pindah caret ====== */
(function(){
  const inputEl = document.querySelector('#input');
  if (!inputEl) return;

  function insertAtCursor(ta, text) {
    const data = String(text || '').replace(/\r\n?/g, '\n');        // normalisasi \n
    const addNL = data.length && !/\n$/.test(data) ? '\n' : '';     // pastikan ada enter di akhir
    const start = ta.selectionStart ?? ta.value.length;
    const end   = ta.selectionEnd   ?? start;
    const before = ta.value.slice(0, start);
    const after  = ta.value.slice(end);
    const insert = data + addNL;
    ta.value = before + insert + after;

    // pindah caret ke akhir sisipan (baris baru kosong, kiri-bawah)
    const pos = before.length + insert.length;
    ta.selectionStart = ta.selectionEnd = pos;
    ta.focus();
    ta.scrollTop = ta.scrollHeight; // scroll ke bawah
    // picu event 'input' supaya renderer YAML jalan (apa pun fungsi kamu: render/syncOutput)
    ta.dispatchEvent(new Event('input', { bubbles: true }));
  }

  // 1) Tangkap paste manual (Ctrl/Cmd+V) di textarea
  inputEl.addEventListener('paste', function(e){
    const cd = e.clipboardData || window.clipboardData;
    if (!cd) return;           // kalau nggak ada, biarkan default
    const text = cd.getData('text');
    if (!text) return;
    e.preventDefault();        // cegah perilaku default
    insertAtCursor(inputEl, text);
  }, true);

  // 2) (Opsional) Ubah tombol "Paste" agar APPEND, bukan replace
  const pasteBtnEl = document.querySelector('#pasteBtn');
  if (pasteBtnEl && navigator.clipboard?.readText) {
    // Lepas handler lama jika perlu (aman diabaikan kalau tidak ada)
    pasteBtnEl.replaceWith(pasteBtnEl.cloneNode(true));
    const newBtn = document.querySelector('#pasteBtn');
    newBtn.addEventListener('click', async () => {
      try {
        const text = await navigator.clipboard.readText();
        if (!text) return;
        insertAtCursor(inputEl, text);
      } catch (_) {
        // fallback: biarkan handler paste manual atau UI kamu yang lain menangani
        // (bisa tampilkan note kalau mau)
      }
    });
  }
})();
  </script>
</body>
</html>
