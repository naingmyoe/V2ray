#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== OUTLINE SECURE PANEL INSTALLER ===${NC}"

# 1. Get Inputs
echo -e "${YELLOW}1. Outline API URL ကို ထည့်ပါ:${NC}"
read -p "API URL: " USER_API_URL

echo -e "${YELLOW}2. Panel အတွက် Password သတ်မှတ်ပါ:${NC}"
read -p "Admin Password: " PANEL_PASSWORD

if [ -z "$USER_API_URL" ] || [ -z "$PANEL_PASSWORD" ]; then
  echo -e "${RED}Data မပြည့်စုံပါ။ ပြန်စမ်းပါ။${NC}"
  exit 1
fi

# 2. Dependencies
echo -e "${YELLOW}[+] Environment ပြင်ဆင်နေပါသည်...${NC}"
apt update -y > /dev/null 2>&1
curl -fsSL https://deb.nodesource.com/setup_18.x | bash - > /dev/null 2>&1
apt install -y nodejs > /dev/null 2>&1
npm install -g pm2 > /dev/null 2>&1

# 3. Setup Directory
DIR="/opt/outline-secure"
mkdir -p $DIR
cd $DIR

# 4. package.json
cat <<EOF > package.json
{
  "name": "outline-secure",
  "version": "2.0.0",
  "main": "server.js",
  "dependencies": {
    "axios": "^1.6.0",
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

npm install > /dev/null 2>&1

# 5. Database File
if [ ! -f data.json ]; then
    echo "{}" > data.json
fi

# 6. Backend Server (Protected)
cat <<EOF > server.js
const express = require('express');
const fs = require('fs');
const cors = require('cors');
const app = express();
const PORT = 8080;
const DB_FILE = 'data.json';
const ADMIN_PASS = "${PANEL_PASSWORD}";

app.use(cors());
app.use(express.json());
app.use(express.static(__dirname));

// Auth Middleware
const checkAuth = (req, res, next) => {
    const pass = req.headers['x-admin-password'];
    if (pass === ADMIN_PASS) next();
    else res.status(403).json({ error: 'Unauthorized' });
};

// Login Route
app.post('/api/login', (req, res) => {
    const { password } = req.body;
    if (password === ADMIN_PASS) res.json({ success: true });
    else res.status(401).json({ success: false });
});

// Protected DB Routes
app.get('/api/db', checkAuth, (req, res) => {
    fs.readFile(DB_FILE, 'utf8', (err, data) => {
        if (err) return res.json({});
        try { res.json(JSON.parse(data)); } catch(e) { res.json({}); }
    });
});

app.post('/api/db', checkAuth, (req, res) => {
    fs.writeFile(DB_FILE, JSON.stringify(req.body, null, 2), (err) => {
        if (err) return res.status(500).send('Error');
        res.send('Saved');
    });
});

app.listen(PORT, () => console.log(\`Secure Server running on port \${PORT}\`));
EOF

# 7. Bot (Auto Guard)
cat <<EOF > bot.js
const axios = require('axios');
const https = require('https');
const fs = require('fs');

const API_URL = "${USER_API_URL}";
const DB_FILE = 'data.json';
const CHECK_INTERVAL = 5000;

const agent = new https.Agent({ rejectUnauthorized: false });
const client = axios.create({ httpsAgent: agent, timeout: 10000 });

function getDB() {
    try { return JSON.parse(fs.readFileSync(DB_FILE, 'utf8')); } 
    catch (e) { return {}; }
}

async function runGuardian() {
    const db = getDB();
    try {
        const [keysRes, metricsRes] = await Promise.all([
            client.get(\`\${API_URL}/access-keys\`),
            client.get(\`\${API_URL}/metrics/transfer\`)
        ]);

        const keys = keysRes.data.accessKeys;
        const usageMap = metricsRes.data.bytesTransferredByUserId || {};
        const today = new Date().toISOString().split('T')[0];

        for (const key of keys) {
            const serverLimit = key.dataLimit ? key.dataLimit.bytes : 0;
            const rawUsage = usageMap[key.id] || 0;
            const config = db[key.id] || { offset: 0, limit: 0, expire: '' };
            
            let netUsage = rawUsage - (config.offset || 0);
            if (netUsage < 0) netUsage = 0;

            const isServerBlocked = serverLimit > 0 && serverLimit <= 5000;
            if (isServerBlocked) continue;

            let shouldBlock = false;
            if (config.expire && config.expire < today) shouldBlock = true;
            if (config.limit > 0 && netUsage >= config.limit) shouldBlock = true;

            if (shouldBlock) {
                console.log(\`Blocking \${key.id}\`);
                await client.put(\`\${API_URL}/access-keys/\${key.id}/data-limit\`, { limit: { bytes: 1 } });
            }
        }
    } catch (error) { console.error(error.message); }
}
setInterval(runGuardian, CHECK_INTERVAL);
EOF

# 8. Frontend (Secure Login UI)
cat <<EOF > index.html
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Secure Panel</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://unpkg.com/lucide@latest"></script>
    <style>@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap');body{font-family:'Inter',sans-serif}.modal{transition:opacity 0.25s ease}</style>
</head>
<body class="bg-slate-100 min-h-screen text-slate-800">

    <!-- LOGIN SCREEN -->
    <div id="auth-screen" class="flex items-center justify-center min-h-screen">
        <div class="bg-white p-8 rounded-2xl shadow-xl w-full max-w-sm border border-slate-200">
            <div class="text-center mb-6">
                <div class="w-16 h-16 bg-slate-900 rounded-full flex items-center justify-center mx-auto mb-4">
                    <i data-lucide="lock" class="w-8 h-8 text-white"></i>
                </div>
                <h2 class="text-2xl font-bold text-slate-800">Admin Login</h2>
            </div>
            <form onsubmit="doLogin(event)" class="space-y-4">
                <input type="password" id="admin-pass" class="w-full p-3 border border-slate-300 rounded-xl outline-none focus:ring-2 focus:ring-slate-800 transition" placeholder="Enter Password" required>
                <button type="submit" id="login-btn" class="w-full bg-slate-900 hover:bg-slate-800 text-white py-3 rounded-xl font-bold transition">Login</button>
            </form>
            <p id="login-error" class="text-red-500 text-xs text-center mt-3 hidden">Incorrect Password</p>
        </div>
    </div>

    <!-- MAIN DASHBOARD (Initially Hidden) -->
    <div id="main-app" class="hidden">
        <nav class="bg-slate-900 text-white shadow-lg sticky top-0 z-40">
            <div class="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
                <div class="flex items-center space-x-3">
                    <div class="bg-indigo-600 p-2 rounded-lg"><i data-lucide="shield-check" class="w-6 h-6 text-white"></i></div>
                    <h1 class="text-xl font-bold">Manager <span class="text-xs text-slate-400">SECURE</span></h1>
                </div>
                <button onclick="logout()" class="p-2 text-slate-400 hover:text-white"><i data-lucide="log-out" class="w-5 h-5"></i></button>
            </div>
        </nav>

        <main class="max-w-7xl mx-auto px-4 py-8">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
                <div class="bg-white p-6 rounded-2xl shadow-sm border"><p class="text-slate-500 text-xs font-bold uppercase">Keys</p><h3 class="text-3xl font-bold mt-1" id="total-keys">0</h3></div>
                <div class="bg-white p-6 rounded-2xl shadow-sm border"><p class="text-slate-500 text-xs font-bold uppercase">Usage</p><h3 class="text-3xl font-bold mt-1" id="total-usage">0 GB</h3></div>
                <button onclick="openModal()" class="bg-slate-900 p-6 rounded-2xl shadow-lg flex items-center justify-center space-x-3 text-white hover:bg-indigo-700 transition"><i data-lucide="plus"></i><span class="font-bold">Create Key</span></button>
            </div>
            <div id="keys-list" class="grid grid-cols-1 lg:grid-cols-2 gap-6"></div>
        </main>
    </div>

    <!-- MODAL -->
    <div id="modal" class="fixed inset-0 bg-slate-900/60 hidden z-50 flex items-center justify-center modal opacity-0">
        <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6 transform scale-95 transition-all">
            <div class="flex justify-between items-center mb-6"><h3 class="text-lg font-bold" id="modal-title">Key</h3><button onclick="closeModal()"><i data-lucide="x"></i></button></div>
            <form id="key-form" class="space-y-4">
                <input type="hidden" id="key-id">
                <input type="text" id="key-name" class="w-full p-3 border rounded-xl" placeholder="Name" required>
                <div class="flex border rounded-xl overflow-hidden"><input type="number" id="key-limit" class="w-full p-3 outline-none" placeholder="Limit"><select id="key-unit" class="bg-slate-50 border-l px-3"><option value="GB">GB</option><option value="MB">MB</option></select></div>
                <input type="date" id="key-expire" class="w-full p-3 border rounded-xl">
                <button type="submit" class="w-full bg-slate-900 text-white py-3 rounded-xl font-bold">Save</button>
            </form>
        </div>
    </div>

    <script>
        const API_URL = "${USER_API_URL}"; 
        let sessionPass = sessionStorage.getItem('panel_pass');
        let dbData = {};

        // INITIALIZE
        document.addEventListener('DOMContentLoaded', () => {
            lucide.createIcons();
            if(sessionPass) tryLogin(sessionPass);
        });

        // LOGIN LOGIC
        async function doLogin(e) {
            e.preventDefault();
            const pass = document.getElementById('admin-pass').value;
            const btn = document.getElementById('login-btn');
            btn.innerText = "Checking..."; btn.disabled = true;
            await tryLogin(pass);
            btn.innerText = "Login"; btn.disabled = false;
        }

        async function tryLogin(pass) {
            try {
                const res = await fetch('/api/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ password: pass })
                });
                const data = await res.json();
                
                if(data.success) {
                    sessionPass = pass;
                    sessionStorage.setItem('panel_pass', pass);
                    document.getElementById('auth-screen').classList.add('hidden');
                    document.getElementById('main-app').classList.remove('hidden');
                    initDashboard();
                } else {
                    document.getElementById('login-error').classList.remove('hidden');
                }
            } catch(e) { alert("Server Connection Error"); }
        }

        function logout() {
            sessionStorage.removeItem('panel_pass');
            location.reload();
        }

        // DATA LOGIC
        async function initDashboard() {
            await fetchDB();
            await refreshData();
            setInterval(async () => { await fetchDB(); await refreshData(); }, 3000);
        }

        async function fetchDB() {
            try {
                const res = await fetch('/api/db', { headers: { 'x-admin-password': sessionPass } });
                if(res.ok) dbData = await res.json();
            } catch(e) {}
        }

        async function saveDB() {
            try {
                await fetch('/api/db', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'x-admin-password': sessionPass },
                    body: JSON.stringify(dbData)
                });
            } catch(e) {}
        }

        async function refreshData() {
            try {
                const [kR, mR] = await Promise.all([fetch(\`\${API_URL}/access-keys\`), fetch(\`\${API_URL}/metrics/transfer\`)]);
                renderDashboard((await kR.json()).accessKeys, (await mR.json()).bytesTransferredByUserId);
            } catch(e) {}
        }

        function formatBytes(b){if(!b)return'0 B';const i=Math.floor(Math.log(b)/Math.log(1024));return(b/Math.pow(1024,i)).toFixed(2)+' '+['B','KB','MB','GB','TB'][i];}

        function renderDashboard(keys, usage) {
            const list = document.getElementById('keys-list'); list.innerHTML = '';
            document.getElementById('total-keys').innerText = keys.length;
            let total = 0; keys.sort((a,b)=>a.id-b.id); const today = new Date().toISOString().split('T')[0];

            keys.forEach(k => {
                const raw = usage[k.id] || 0;
                const conf = dbData[k.id] || { offset: 0, limit: 0, expire: '' };
                let net = raw - (conf.offset || 0); if(net<0){net=raw; conf.offset=0; saveDB();}
                total += net;

                const sLim = k.dataLimit ? k.dataLimit.bytes : 0;
                const isBlocked = sLim > 0 && sLim <= 5000;
                
                let st='Active', stCol='text-green-600', pg='bg-indigo-500';
                if(isBlocked) { st='Disabled'; stCol='text-slate-400'; pg='bg-slate-300'; }
                if(conf.expire && conf.expire < today && isBlocked) st='Expired';
                if(conf.limit > 0 && net >= conf.limit && isBlocked) st='Limit Reached';

                let pct = conf.limit > 0 ? Math.min((net/conf.limit)*100, 100) : 5;
                let limTxt = conf.limit > 0 ? formatBytes(conf.limit) : 'Unlimited';
                let url = k.name ? \`\${k.accessUrl.split('#')[0]}#\${encodeURIComponent(k.name)}\` : k.accessUrl;

                list.innerHTML += \`
                <div class="bg-white rounded-2xl p-5 border \${isBlocked?'bg-slate-50 opacity-80':''}">
                    <div class="flex justify-between mb-3">
                        <div><div class="font-bold">\${k.name||'No Name'}</div><div class="text-xs \${stCol} font-bold">\${st}</div></div>
                        <button onclick="toggle('\${k.id}',\${isBlocked})" class="w-10 h-6 rounded-full \${isBlocked?'bg-slate-300':'bg-emerald-500'} relative"><span class="w-4 h-4 bg-white rounded-full absolute top-1 transition-all \${isBlocked?'left-1':'left-5'}"></span></button>
                    </div>
                    <div class="mb-3 text-xs font-bold text-slate-500 flex justify-between"><span>\${formatBytes(net)}</span><span>\${limTxt}</span></div>
                    <div class="w-full bg-slate-100 h-2 rounded-full mb-4 overflow-hidden"><div class="\${pg} h-2" style="width:\${pct}%"></div></div>
                    <div class="flex justify-between border-t pt-3">
                        <div class="space-x-1">
                            <button onclick="edit('\${k.id}','\${(k.name||'').replace(/'/g,"\\\\'")}')" class="p-2 hover:bg-slate-100 rounded"><i data-lucide="settings-2" class="w-4"></i></button>
                            <button onclick="reset('\${k.id}',\${raw})" class="p-2 hover:text-orange-500"><i data-lucide="rotate-ccw" class="w-4"></i></button>
                            <button onclick="del('\${k.id}')" class="p-2 hover:text-red-500"><i data-lucide="trash-2" class="w-4"></i></button>
                        </div>
                        <button onclick="copy('\${url}')" class="text-xs border px-2 rounded">Copy</button>
                    </div>
                </div>\`;
            });
            document.getElementById('total-usage').innerText = formatBytes(total);
            lucide.createIcons();
        }

        async function toggle(id, isB) {
            try {
                if(isB) await fetch(\`\${API_URL}/access-keys/\${id}/data-limit\`, {method:'DELETE'});
                else await fetch(\`\${API_URL}/access-keys/\${id}/data-limit\`, {method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify({limit:{bytes:1}})});
                refreshData();
            } catch(e){}
        }

        async function reset(id, raw) {
            if(!confirm("Reset Traffic?")) return;
            dbData[id] = { ...(dbData[id]||{}), offset: raw }; await saveDB();
            await fetch(\`\${API_URL}/access-keys/\${id}/data-limit\`, {method:'DELETE'}); 
            refreshData();
        }

        async function del(id) {
            if(!confirm("Delete?")) return;
            await fetch(\`\${API_URL}/access-keys/\${id}\`, {method:'DELETE'});
            delete dbData[id]; await saveDB(); refreshData();
        }

        function copy(t){const el=document.createElement('textarea');el.value=t;document.body.appendChild(el);el.select();document.execCommand('copy');document.body.removeChild(el);alert("Copied");}

        // Modal
        const m = document.getElementById('modal');
        function closeModal(){m.classList.add('hidden'); m.classList.add('opacity-0');}
        function openModal(){document.getElementById('key-form').reset(); document.getElementById('key-id').value=''; const d=new Date(); d.setDate(d.getDate()+30); document.getElementById('key-expire').value=d.toISOString().split('T')[0]; m.classList.remove('hidden'); setTimeout(()=>m.classList.remove('opacity-0'),10);}
        
        function edit(id, name) {
            document.getElementById('key-id').value = id;
            document.getElementById('key-name').value = name;
            const c = dbData[id] || {};
            if(c.limit>0) {
                if(c.limit>=1073741824){document.getElementById('key-limit').value=(c.limit/1073741824).toFixed(2);document.getElementById('key-unit').value='GB';}
                else{document.getElementById('key-limit').value=(c.limit/1048576).toFixed(2);document.getElementById('key-unit').value='MB';}
            } else document.getElementById('key-limit').value='';
            document.getElementById('key-expire').value = c.expire || '';
            m.classList.remove('hidden'); setTimeout(()=>m.classList.remove('opacity-0'),10);
        }

        document.getElementById('key-form').addEventListener('submit', async(e)=>{
            e.preventDefault();
            const id=document.getElementById('key-id').value; const name=document.getElementById('key-name').value;
            const lv=parseFloat(document.getElementById('key-limit').value); const u=document.getElementById('key-unit').value;
            const exp=document.getElementById('key-expire').value;

            try {
                let tid=id; if(!tid){const r=await fetch(\`\${API_URL}/access-keys\`,{method:'POST'});const d=await r.json();tid=d.id; dbData[tid]={offset:0,limit:0,expire:''};}
                await fetch(\`\${API_URL}/access-keys/\${tid}/name\`,{method:'PUT',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:\`name=\${encodeURIComponent(name)}\`});
                
                let b=0; if(lv>0) b=(u==='GB')?Math.floor(lv*1024*1024*1024):Math.floor(lv*1024*1024);
                dbData[tid] = { ...(dbData[tid]||{offset:0}), limit:b, expire:exp };
                await saveDB(); await fetch(\`\${API_URL}/access-keys/\${tid}/data-limit\`,{method:'DELETE'});
                closeModal(); refreshData();
            } catch(e){}
        });
    </script>
</body>
</html>
EOF

# 9. Final PM2 Setup
echo -e "${YELLOW}[+] Services များကို စတင်နေပါသည်...${NC}"
pm2 delete outline-secure 2>/dev/null
pm2 delete outline-guard 2>/dev/null

pm2 start server.js --name "outline-secure"
pm2 start bot.js --name "outline-guard"

pm2 save
pm2 startup

# 10. Firewall
ufw allow 8080/tcp > /dev/null 2>&1

IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   INSTALLATION COMPLETE! (Secure Edition)    ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "Web Panel Link:"
echo -e "${YELLOW}http://${IP}:8080${NC}"
echo -e "Password: ${YELLOW}${PANEL_PASSWORD}${NC}"
echo -e "${GREEN}==============================================${NC}"
