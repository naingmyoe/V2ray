#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== OUTLINE VPS DATABASE EDITION INSTALLER ===${NC}"

# 1. Get API URL
echo -e "${YELLOW}Outline API URL ကို ထည့်ပါ:${NC}"
read -p "API URL: " USER_API_URL

if [ -z "$USER_API_URL" ]; then
  echo "API URL မထည့်ထားပါ။"
  exit 1
fi

# 2. Setup Env
apt update -y
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs
npm install -g pm2

# 3. Directory Setup
DIR="/opt/outline-vps-db"
mkdir -p $DIR
cd $DIR

# 4. Create package.json
cat <<EOF > package.json
{
  "name": "outline-vps-db",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "axios": "^1.6.0",
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "body-parser": "^1.20.2"
  }
}
EOF

npm install

# 5. Create Initial Database
echo "{}" > data.json

# 6. Create Backend Server (server.js)
# This saves data to VPS file instead of LocalStorage
cat <<EOF > server.js
const express = require('express');
const fs = require('fs');
const cors = require('cors');
const path = require('path');
const app = express();
const PORT = 8080;
const DB_FILE = 'data.json';

app.use(cors());
app.use(express.json());
app.use(express.static(__dirname)); // Serve index.html

// Read Database
app.get('/api/db', (req, res) => {
    fs.readFile(DB_FILE, 'utf8', (err, data) => {
        if (err) return res.json({});
        try { res.json(JSON.parse(data)); } catch(e) { res.json({}); }
    });
});

// Write Database
app.post('/api/db', (req, res) => {
    const newData = req.body;
    fs.writeFile(DB_FILE, JSON.stringify(newData, null, 2), (err) => {
        if (err) return res.status(500).send('Error saving');
        res.send('Saved');
    });
});

app.listen(PORT, () => console.log(\`Server running on port \${PORT}\`));
EOF

# 7. Create Smart Bot (bot.js)
# This checks Offset Limit from data.json
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
    const now = new Date().toLocaleString('en-US', { hour12: false });
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
            
            // VPS Database Config
            const config = db[key.id] || { offset: 0, limit: 0, expire: '' };
            
            // Calculate NET USAGE (Raw - Offset)
            let netUsage = rawUsage - (config.offset || 0);
            if (netUsage < 0) netUsage = 0;

            // Determine if Server Blocked (1 byte limit)
            const isServerBlocked = serverLimit > 0 && serverLimit <= 5000;

            if (isServerBlocked) continue; // Already blocked, skip

            let shouldBlock = false;
            let reason = "";

            // 1. Check Expiry
            if (config.expire && config.expire < today) {
                shouldBlock = true;
                reason = \`EXPIRED (\${config.expire})\`;
            }

            // 2. Check Offset Limit
            if (!shouldBlock && config.limit > 0 && netUsage >= config.limit) {
                shouldBlock = true;
                reason = \`LIMIT REACHED (Used: \${(netUsage/1024/1024).toFixed(2)} MB)\`;
            }

            // Action
            if (shouldBlock) {
                console.log(\`[\${now}] 🚫 Blocking \${key.id}: \${reason}\`);
                await client.put(\`\${API_URL}/access-keys/\${key.id}/data-limit\`, {
                    limit: { bytes: 1 }
                });
            }
        }
    } catch (error) {
        console.error(\`[\${now}] Error: \${error.message}\`);
    }
}

console.log("🚀 Smart Offset Bot Started...");
setInterval(runGuardian, CHECK_INTERVAL);
EOF

# 8. Create Frontend (index.html)
cat <<EOF > index.html
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Outline VPS Manager</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://unpkg.com/lucide@latest"></script>
    <style>@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap');body{font-family:'Inter',sans-serif}.modal{transition:opacity 0.25s ease}</style>
</head>
<body class="bg-slate-100 min-h-screen text-slate-800">
    <nav class="bg-slate-900 text-white shadow-lg sticky top-0 z-40">
        <div class="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
            <div class="flex items-center space-x-3">
                <div class="bg-indigo-600 p-2 rounded-lg"><i data-lucide="database" class="w-6 h-6 text-white"></i></div>
                <div><h1 class="text-xl font-bold tracking-tight">Outline Manager</h1><p class="text-[10px] text-slate-400 uppercase tracking-widest font-semibold">VPS Database Edition</p></div>
            </div>
            <div id="status-badge" class="hidden md:flex items-center px-3 py-1 bg-slate-800 rounded-full border border-slate-700"><span class="w-2 h-2 bg-emerald-500 rounded-full mr-2 animate-pulse"></span><span class="text-xs text-emerald-400 font-medium">VPS Storage Active</span></div>
        </div>
    </nav>
    <main class="max-w-7xl mx-auto px-4 py-8">
        <!-- Stats -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
            <div class="bg-white p-6 rounded-2xl shadow-sm border border-slate-200"><p class="text-slate-500 text-xs font-bold uppercase">Total Keys</p><h3 class="text-3xl font-bold text-slate-800 mt-1" id="total-keys">0</h3></div>
            <div class="bg-white p-6 rounded-2xl shadow-sm border border-slate-200"><p class="text-slate-500 text-xs font-bold uppercase">Session Usage</p><h3 class="text-3xl font-bold text-slate-800 mt-1" id="total-usage">0 GB</h3></div>
            <button onclick="openCreateModal()" class="bg-slate-900 p-6 rounded-2xl shadow-lg flex items-center justify-center space-x-3 hover:bg-indigo-700 transition"><i data-lucide="plus" class="w-6 h-6 text-white"></i><span class="text-white font-bold text-lg">Create Key</span></button>
        </div>
        <!-- List -->
        <div id="keys-list" class="grid grid-cols-1 lg:grid-cols-2 gap-6"></div>
    </main>

    <!-- Modal -->
    <div id="modal-overlay" class="fixed inset-0 bg-slate-900/60 hidden z-50 flex items-center justify-center backdrop-blur-sm opacity-0 modal">
        <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md transform transition-all scale-95" id="modal-content">
            <div class="p-6 border-b border-slate-100 flex justify-between items-center"><h3 class="text-lg font-bold text-slate-800" id="modal-title">Edit Key</h3><button onclick="closeModal()" class="text-slate-400"><i data-lucide="x" class="w-5 h-5"></i></button></div>
            <form id="key-form" class="p-6 space-y-5"><input type="hidden" id="key-id">
                <div><label class="block text-xs font-bold text-slate-500 uppercase mb-1">Name</label><input type="text" id="key-name" class="w-full p-3 border border-slate-300 rounded-xl outline-none" required></div>
                <div class="grid grid-cols-2 gap-4">
                    <div><label class="block text-xs font-bold text-slate-500 uppercase mb-1">Limit</label><div class="flex border border-slate-300 rounded-xl overflow-hidden"><input type="number" id="key-limit" class="w-full p-3 outline-none" placeholder="Unl"><select id="key-unit" class="bg-slate-50 border-l px-3"><option value="GB">GB</option><option value="MB">MB</option></select></div></div>
                    <div><label class="block text-xs font-bold text-slate-500 uppercase mb-1">Expire</label><input type="date" id="key-expire" class="w-full p-3 border border-slate-300 rounded-xl outline-none"></div>
                </div>
                <button type="submit" id="save-btn" class="w-full bg-slate-900 hover:bg-indigo-700 text-white py-3.5 rounded-xl font-bold shadow-lg">Save</button>
            </form>
        </div>
    </div>

    <script>
        const API_URL = "${USER_API_URL}"; 
        let dbData = {}; 
        
        document.addEventListener('DOMContentLoaded', () => { lucide.createIcons(); initApp(); });

        async function initApp() {
            await fetchDB();
            await refreshData();
            setInterval(async () => { await fetchDB(); await refreshData(); }, 3000);
        }

        // --- VPS DATABASE SYNC ---
        async function fetchDB() {
            try { const res = await fetch('/api/db'); dbData = await res.json(); } catch(e) {}
        }
        async function saveDB() {
            try { await fetch('/api/db', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(dbData) }); } catch(e) {}
        }

        async function refreshData() {
            try {
                const [keysRes, metricsRes] = await Promise.all([ fetch(\`\${API_URL}/access-keys\`), fetch(\`\${API_URL}/metrics/transfer\`) ]);
                const keysData = await keysRes.json();
                const metricsData = await metricsRes.json();
                renderDashboard(keysData.accessKeys, metricsData.bytesTransferredByUserId);
            } catch(e) {}
        }

        function formatBytes(b){if(!b)return'0 B';const i=Math.floor(Math.log(b)/Math.log(1024));return(b/Math.pow(1024,i)).toFixed(2)+' '+['B','KB','MB','GB','TB'][i];}

        function renderDashboard(keys, usage) {
            const list = document.getElementById('keys-list'); list.innerHTML=''; 
            document.getElementById('total-keys').innerText=keys.length;
            let totalNet=0;
            keys.sort((a,b)=>parseInt(a.id)-parseInt(b.id)); const today=new Date().toISOString().split('T')[0];

            keys.forEach(k => {
                const rawUsage = usage[k.id] || 0;
                const config = dbData[k.id] || { offset: 0, limit: 0, expire: '' };
                
                // NET USAGE Calculation
                let netUsage = rawUsage - (config.offset || 0);
                if(netUsage < 0) { netUsage = rawUsage; config.offset = 0; saveDB(); }
                totalNet += netUsage;

                // Status
                const serverLimit = k.dataLimit ? k.dataLimit.bytes : 0;
                const isBlocked = serverLimit > 0 && serverLimit <= 5000;
                const isOverLimit = config.limit > 0 && netUsage >= config.limit;
                const isExpired = config.expire && config.expire < today;

                let st='Active', sc='text-green-600', pc='bg-emerald-500';
                if(isBlocked) { st='Disabled'; sc='text-slate-400'; pc='bg-slate-300'; }
                if(isBlocked && isOverLimit) st='Limit Reached';
                if(isBlocked && isExpired) st='Expired';

                let p=0; if(config.limit > 0) p = Math.min((netUsage/config.limit)*100, 100);
                let limitText = config.limit > 0 ? formatBytes(config.limit) : 'Unlimited';
                
                let finalUrl = k.accessUrl;
                if(k.name) finalUrl = \`\${k.accessUrl.split('#')[0]}#\${encodeURIComponent(k.name)}\`;

                list.innerHTML += \`
                <div class="bg-white rounded-2xl shadow-sm border p-5 hover:shadow-md transition-all \${isBlocked?'opacity-80 bg-slate-50':''}">
                    <div class="flex justify-between items-center mb-3">
                        <div class="flex items-center">
                            <div class="w-10 h-10 rounded-full \${isBlocked?'bg-slate-200 text-slate-500':'bg-indigo-50 text-indigo-600'} font-bold flex items-center justify-center mr-3">\${k.id}</div>
                            <div><div class="font-bold text-slate-800">\${k.name||'No Name'}</div><div class="text-xs \${sc} font-bold">\${st} \${config.expire?'('+config.expire+')':''}</div></div>
                        </div>
                        <button onclick="toggleKey('\${k.id}',\${isBlocked})" class="w-12 h-6 rounded-full relative transition-colors \${!isBlocked?'bg-emerald-500':'bg-slate-300'}"><span class="w-4 h-4 bg-white rounded-full absolute top-1 transition-all \${!isBlocked?'left-7':'left-1'}"></span></button>
                    </div>
                    <div class="mb-4">
                        <div class="flex justify-between text-xs mb-1 font-bold text-slate-500"><span>\${formatBytes(netUsage)}</span><span>\${limitText}</span></div>
                        <div class="w-full bg-slate-100 rounded-full h-2"><div class="\${pc} h-2 rounded-full" style="width:\${p}%"></div></div>
                    </div>
                    <div class="flex justify-between pt-3 border-t">
                        <div class="space-x-1">
                            <button onclick="editKey('\${k.id}','\${(k.name||'').replace(/'/g,"\\\\'")}')" class="p-2 hover:bg-slate-100 rounded"><i data-lucide="settings-2" class="w-4 h-4"></i></button>
                            <button onclick="resetTraffic('\${k.id}', \${rawUsage})" class="p-2 hover:text-orange-500 rounded" title="Reset Traffic (Updates Offset)"><i data-lucide="rotate-ccw" class="w-4 h-4"></i></button>
                            <button onclick="deleteKey('\${k.id}')" class="p-2 hover:text-red-500 rounded"><i data-lucide="trash-2" class="w-4 h-4"></i></button>
                        </div>
                        <button onclick="copyKey('\${finalUrl}')" class="text-xs font-bold text-slate-500 border px-2 py-1 rounded">Copy</button>
                    </div>
                </div>\`;
            });
            document.getElementById('total-usage').innerText = formatBytes(totalNet);
            lucide.createIcons();
        }

        // --- ACTIONS ---
        async function toggleKey(id, isBlocked) {
            try {
                if(isBlocked) await fetch(\`\${API_URL}/access-keys/\${id}/data-limit\`, {method:'DELETE'});
                else await fetch(\`\${API_URL}/access-keys/\${id}/data-limit\`, {method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify({limit:{bytes:1}})});
                refreshData();
            } catch(e){}
        }

        async function resetTraffic(id, raw) {
            if(!confirm("Reset Traffic to 0?")) return;
            dbData[id] = { ...(dbData[id]||{}), offset: raw };
            await saveDB();
            await fetch(\`\${API_URL}/access-keys/\${id}/data-limit\`, {method:'DELETE'}); // Unblock
            refreshData();
        }

        async function deleteKey(id) {
            if(!confirm("Delete?")) return;
            await fetch(\`\${API_URL}/access-keys/\${id}\`, {method:'DELETE'});
            delete dbData[id]; await saveDB(); refreshData();
        }

        function copyKey(t){const el=document.createElement('textarea');el.value=t;document.body.appendChild(el);el.select();document.execCommand('copy');document.body.removeChild(el);alert("Copied");}

        // MODAL
        const modal=document.getElementById('modal-overlay');
        function closeModal(){modal.classList.add('hidden');}
        function openCreateModal(){document.getElementById('key-form').reset();document.getElementById('key-id').value='';modal.classList.remove('hidden');}
        
        function editKey(id, name) {
            document.getElementById('key-id').value = id;
            document.getElementById('key-name').value = name;
            const conf = dbData[id] || {};
            if(conf.limit > 0) {
                if(conf.limit >= 1073741824) { document.getElementById('key-limit').value = (conf.limit/1073741824).toFixed(2); document.getElementById('key-unit').value='GB'; }
                else { document.getElementById('key-limit').value = (conf.limit/1048576).toFixed(2); document.getElementById('key-unit').value='MB'; }
            } else document.getElementById('key-limit').value='';
            document.getElementById('key-expire').value = conf.expire || '';
            modal.classList.remove('hidden');
        }

        document.getElementById('key-form').addEventListener('submit', async (e)=>{
            e.preventDefault(); const btn=document.getElementById('save-btn'); btn.innerText='Saving...'; btn.disabled=true;
            const id=document.getElementById('key-id').value; const name=document.getElementById('key-name').value;
            const date=document.getElementById('key-expire').value; const lv=parseFloat(document.getElementById('key-limit').value);
            const u=document.getElementById('key-unit').value;

            try {
                let tid=id;
                if(!tid) { 
                    const r=await fetch(\`\${API_URL}/access-keys\`, {method:'POST'}); const d=await r.json(); tid=d.id; 
                    dbData[tid] = { offset: 0, limit: 0, expire: '' }; // Init DB
                }
                
                await fetch(\`\${API_URL}/access-keys/\${tid}/name\`, {method:'PUT', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:\`name=\${encodeURIComponent(name)}\`});
                
                let b = 0;
                if(lv>0) b = (u==='GB') ? Math.floor(lv*1024*1024*1024) : Math.floor(lv*1024*1024);
                
                dbData[tid] = { ...(dbData[tid]||{offset:0}), limit: b, expire: date };
                await saveDB();
                
                // Ensure server is unblocked so we control via offset
                await fetch(\`\${API_URL}/access-keys/\${tid}/data-limit\`, {method:'DELETE'});

                closeModal(); refreshData();
            } catch(e){} finally { btn.innerText='Save'; btn.disabled=false; }
        });
    </script>
</body>
</html>
EOF

# 9. PM2 Setup (Run Server + Bot)
pm2 delete outline-server 2>/dev/null
pm2 delete outline-bot 2>/dev/null

pm2 start server.js --name "outline-server"
pm2 start bot.js --name "outline-bot"

pm2 save
pm2 startup

# 10. Final Firewall
ufw allow 8080/tcp > /dev/null 2>&1

IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   INSTALLATION COMPLETE! (DB Edition)        ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "Web Panel: ${YELLOW}http://${IP}:8080${NC}"
echo -e "Data stored in: ${YELLOW}/opt/outline-vps-db/data.json${NC}"
