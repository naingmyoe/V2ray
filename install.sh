#!/bin/bash

# အရောင်များသတ်မှတ်ခြင်း
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   OUTLINE MANAGER ULTIMATE INSTALLER    ${NC}"
echo -e "${GREEN}=========================================${NC}"

# 1. Root စစ်ဆေးခြင်း
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Please run as root (sudo ./install.sh)${NC}"
  exit
fi

# 2. API URL တောင်းခံခြင်း
echo -e "${YELLOW}Outline Management API URL ကို ထည့်သွင်းပေးပါ:${NC}"
echo -e "(Example: https://1.2.3.4:12345/SecretKey...)"
read -p "API URL: " USER_API_URL

if [ -z "$USER_API_URL" ]; then
  echo -e "${RED}API URL မထည့်သွင်းထားပါ။ Installation ရပ်တန့်လိုက်ပါပြီ။${NC}"
  exit 1
fi

# 3. System Update & Dependencies Install
echo -e "${YELLOW}[+] System Updating & Installing Node.js...${NC}"
apt update -y
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# 4. Global Tools Install
echo -e "${YELLOW}[+] Installing PM2 & HTTP-Server...${NC}"
npm install -g pm2 http-server

# 5. Setup Directory
INSTALL_DIR="/opt/outline-manager"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# 6. Creating package.json
echo -e "${YELLOW}[+] Creating Config Files...${NC}"
cat <<EOF > package.json
{
  "name": "outline-manager-pro",
  "version": "1.0.0",
  "description": "Outline Manager & Bot",
  "main": "bot.js",
  "dependencies": {
    "axios": "^1.6.0"
  }
}
EOF

# Install Local Dependencies
npm install

# 7. Creating bot.js (Auto Guard)
cat <<EOF > bot.js
const axios = require('axios');
const https = require('https');

// CONFIGURATION
const API_URL = "${USER_API_URL}"; 
const CHECK_INTERVAL = 10000; // 10 Seconds
const REQUEST_TIMEOUT = 30000; // 30 Seconds

const agent = new https.Agent({ rejectUnauthorized: false, keepAlive: true });
const client = axios.create({ httpsAgent: agent, timeout: REQUEST_TIMEOUT });

function formatBytes(bytes) {
    if (!bytes) return '0 B';
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return (bytes / Math.pow(1024, i)).toFixed(2) + ' ' + ['B', 'KB', 'MB', 'GB', 'TB'][i];
}

async function runGuardian() {
    const now = new Date().toLocaleString('en-US', { hour12: false });
    try {
        const [keysRes, metricsRes] = await Promise.all([
            client.get(\`\${API_URL}/access-keys\`),
            client.get(\`\${API_URL}/metrics/transfer\`)
        ]);

        const keys = keysRes.data.accessKeys;
        const usageMap = metricsRes.data.bytesTransferredByUserId || {};
        const today = new Date().toISOString().split('T')[0];

        for (const key of keys) {
            const limitBytes = key.dataLimit ? key.dataLimit.bytes : 0;
            const usedBytes = usageMap[key.id] || 0;
            const isBlocked = limitBytes > 0 && limitBytes <= 5000;

            if (isBlocked) continue; 

            let shouldBlock = false;
            let reason = "";

            if (key.name && key.name.includes('|')) {
                const parts = key.name.split('|');
                const dateStr = parts[parts.length - 1].trim();
                if (/^\d{4}-\d{2}-\d{2}$/.test(dateStr) && dateStr < today) {
                    shouldBlock = true;
                    reason = \`EXPIRED (\${dateStr})\`;
                }
            }

            if (!shouldBlock && limitBytes > 5000 && usedBytes >= limitBytes) {
                shouldBlock = true;
                reason = \`DATA LIMIT (\${formatBytes(usedBytes)} / \${formatBytes(limitBytes)})\`;
            }

            if (shouldBlock) {
                console.log(\`[\${now}] 🚫 Blocking Key ID \${key.id}: \${reason}\`);
                await client.put(\`\${API_URL}/access-keys/\${key.id}/data-limit\`, { limit: { bytes: 1 } });
            }
        }
    } catch (error) {
        console.error(\`[\${now}] ⚠️ Error: \${error.message}\`);
    }
}

console.log("🚀 Outline Auto-Guard Started...");
runGuardian();
setInterval(runGuardian, CHECK_INTERVAL);
EOF

# 8. Creating index.html (Web Panel Ultimate)
cat <<EOF > index.html
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Outline Ultimate Manager</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://unpkg.com/lucide@latest"></script>
    <style>@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap');body{font-family:'Inter',sans-serif}.modal{transition:opacity 0.25s ease}</style>
</head>
<body class="bg-slate-100 min-h-screen text-slate-800">
    <nav class="bg-slate-900 text-white shadow-lg sticky top-0 z-40">
        <div class="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
            <div class="flex items-center space-x-3">
                <div class="bg-indigo-600 p-2 rounded-lg"><i data-lucide="shield-check" class="w-6 h-6 text-white"></i></div>
                <div><h1 class="text-xl font-bold tracking-tight">Outline Manager</h1><p class="text-[10px] text-slate-400 uppercase tracking-widest font-semibold">Ultimate Edition</p></div>
            </div>
            <div id="nav-status" class="hidden flex items-center space-x-4">
                <div class="hidden md:flex items-center px-3 py-1 bg-slate-800 rounded-full border border-slate-700"><span class="w-2 h-2 bg-emerald-500 rounded-full mr-2 animate-pulse"></span><span class="text-xs text-emerald-400 font-medium">System Active</span></div>
                <button onclick="disconnect()" class="p-2 text-slate-400 hover:text-white rounded-lg"><i data-lucide="log-out" class="w-5 h-5"></i></button>
            </div>
        </div>
    </nav>
    <main class="max-w-7xl mx-auto px-4 py-8">
        <div id="login-section" class="max-w-lg mx-auto mt-16">
            <div class="bg-white rounded-2xl shadow-xl p-8 border border-slate-200">
                <h2 class="text-2xl font-bold text-center text-slate-800 mb-6">Server Connection</h2>
                <form onsubmit="connectServer(event)" class="space-y-4">
                    <input type="password" id="api-url" class="w-full p-3 border border-slate-300 rounded-xl focus:ring-2 focus:ring-indigo-500 outline-none" placeholder="https://1.2.3.4:xxxxx/SecretKey..." required>
                    <button type="submit" id="connect-btn" class="w-full bg-indigo-600 hover:bg-indigo-700 text-white py-3.5 rounded-xl font-bold shadow-lg transition">Connect</button>
                </form>
                <div id="ssl-help" class="hidden mt-6 p-4 bg-orange-50 border border-orange-200 rounded-xl text-sm text-orange-800"><p class="font-bold">Connection Failed?</p><a href="#" id="ssl-link" target="_blank" class="underline">Click here to accept SSL Certificate</a></div>
            </div>
        </div>
        <div id="dashboard" class="hidden space-y-8">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div class="bg-white p-6 rounded-2xl shadow-sm border border-slate-200"><p class="text-slate-500 text-xs font-bold uppercase">Total Keys</p><h3 class="text-3xl font-bold text-slate-800 mt-1" id="total-keys">0</h3></div>
                <div class="bg-white p-6 rounded-2xl shadow-sm border border-slate-200"><p class="text-slate-500 text-xs font-bold uppercase">Total Usage</p><h3 class="text-3xl font-bold text-slate-800 mt-1" id="total-usage">0 GB</h3></div>
                <button onclick="openCreateModal()" class="bg-slate-900 p-6 rounded-2xl shadow-lg flex items-center justify-center space-x-3 hover:bg-indigo-700 transition"><i data-lucide="plus" class="w-6 h-6 text-white"></i><span class="text-white font-bold text-lg">Create Key</span></button>
            </div>
            <div id="keys-list" class="grid grid-cols-1 lg:grid-cols-2 gap-6"></div>
        </div>
    </main>
    <div id="modal-overlay" class="fixed inset-0 bg-slate-900/60 hidden z-50 flex items-center justify-center backdrop-blur-sm opacity-0 modal">
        <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md transform transition-all scale-95" id="modal-content">
            <div class="p-6 border-b border-slate-100 flex justify-between items-center"><h3 class="text-lg font-bold text-slate-800" id="modal-title">New Key</h3><button onclick="closeModal()" class="text-slate-400"><i data-lucide="x" class="w-5 h-5"></i></button></div>
            <form id="key-form" class="p-6 space-y-5"><input type="hidden" id="key-id"><div><label class="block text-xs font-bold text-slate-500 uppercase mb-1">Name</label><input type="text" id="key-name" class="w-full p-3 border border-slate-300 rounded-xl outline-none" required></div><div class="grid grid-cols-2 gap-4"><div><label class="block text-xs font-bold text-slate-500 uppercase mb-1">Limit</label><div class="flex border border-slate-300 rounded-xl overflow-hidden"><input type="number" id="key-limit" class="w-full p-3 outline-none" placeholder="Unl"><select id="key-unit" class="bg-slate-50 border-l px-3"><option value="GB">GB</option><option value="MB">MB</option></select></div></div><div><label class="block text-xs font-bold text-slate-500 uppercase mb-1">Expire</label><input type="date" id="key-expire" class="w-full p-3 border border-slate-300 rounded-xl outline-none"></div></div><button type="submit" id="save-btn" class="w-full bg-slate-900 hover:bg-indigo-700 text-white py-3.5 rounded-xl font-bold shadow-lg">Save</button></form>
        </div>
    </div>
    <div id="toast" class="fixed bottom-5 right-5 bg-slate-800 text-white px-6 py-4 rounded-xl shadow-2xl transform translate-y-24 transition-transform duration-300 flex items-center z-[60] max-w-sm"><span id="toast-msg">Msg</span></div>
    <script>
        let apiUrl = localStorage.getItem('outline_api_url') || '';
        let refreshInterval; const REFRESH_RATE=5000;
        document.addEventListener('DOMContentLoaded',()=>{lucide.createIcons();if(apiUrl){document.getElementById('api-url').value=apiUrl;startConnectionProcess();}});
        function showToast(m){const t=document.getElementById('toast');document.getElementById('toast-msg').innerText=m;t.classList.remove('translate-y-24');setTimeout(()=>t.classList.add('translate-y-24'),3000);}
        function disconnect(){localStorage.removeItem('outline_api_url');location.reload();}
        function connectServer(e){e.preventDefault();let u=document.getElementById('api-url').value.trim();if(u.endsWith('/'))u=u.slice(0,-1);apiUrl=u;startConnectionProcess();}
        async function startConnectionProcess(){
            const btn=document.getElementById('connect-btn'); btn.innerText='Connecting...'; btn.disabled=true;
            document.getElementById('ssl-help').classList.add('hidden'); document.getElementById('ssl-link').href=apiUrl;
            try{const r=await fetch(\`\${apiUrl}/server\`);if(!r.ok)throw new Error();localStorage.setItem('outline_api_url',apiUrl);
            document.getElementById('login-section').classList.add('hidden');document.getElementById('dashboard').classList.remove('hidden');document.getElementById('nav-status').classList.remove('hidden');
            await refreshData(); refreshInterval=setInterval(refreshData,REFRESH_RATE);}catch(e){document.getElementById('ssl-help').classList.remove('hidden');btn.innerText='Connect';btn.disabled=false;}
        }
        async function refreshData(){try{const [k,m]=await Promise.all([fetch(\`\${apiUrl}/access-keys\`),fetch(\`\${apiUrl}/metrics/transfer\`)]);const kd=await k.json();const md=await m.json();renderDashboard(kd.accessKeys,md.bytesTransferredByUserId);}catch(e){}}
        function formatBytes(b){if(!b)return'0 B';const i=Math.floor(Math.log(b)/Math.log(1024));return(b/Math.pow(1024,i)).toFixed(2)+' '+['B','KB','MB','GB','TB'][i];}
        async function renderDashboard(keys,usage){
            const l=document.getElementById('keys-list'); l.innerHTML=''; document.getElementById('total-keys').innerText=keys.length;
            let tb=0; Object.values(usage).forEach(b=>tb+=b); document.getElementById('total-usage').innerText=formatBytes(tb);
            keys.sort((a,b)=>parseInt(a.id)-parseInt(b.id)); const today=new Date().toISOString().split('T')[0];
            for(const k of keys){
                const lb=k.dataLimit?k.dataLimit.bytes:0; const ub=usage[k.id]||0;
                let dn=k.name||'No Name', rn=dn, ed=null;
                if(dn.includes('|')){rn=dn.split('|')[0].trim();const d=dn.split('|')[1].trim();if(/^\d{4}-\d{2}-\d{2}$/.test(d))ed=d;}
                let url=k.accessUrl; if(k.name)url=\`\${k.accessUrl.split('#')[0]}#\${encodeURIComponent(dn)}\`;
                const isB=lb>0&&lb<=5000, isE=ed&&ed<today, isL=lb>5000&&ub>=lb;
                if(!isB&&(isE||isL)) await autoBlockKey(k.id);
                let st=isB?'Disabled':'Active', sc=isB?'text-slate-400':'text-green-600', pc=isB?'bg-slate-300':(lb>5000?'bg-indigo-500':'bg-emerald-500');
                if(isB&&isE)st='Expired'; let p=0; if(lb>5000&&!isB)p=Math.min((ub/lb)*100,100);
                l.innerHTML+=\`<div class="bg-white rounded-2xl shadow-sm border p-5 hover:shadow-md transition-all \${isB?'bg-slate-50 opacity-90':''}"><div class="flex justify-between items-center mb-3"><div class="flex items-center"><div class="w-10 h-10 rounded-full \${isB?'bg-slate-200 text-slate-500':'bg-indigo-50 text-indigo-600'} font-bold flex items-center justify-center mr-3">\${k.id}</div><div><div class="font-bold text-slate-800">\${rn}</div><div class="text-xs \${sc} font-bold">\${st} \${ed?'(Exp:'+ed+')':''}</div></div></div><button onclick="toggleKey('\${k.id}',\${isB})" class="w-12 h-6 rounded-full relative transition-colors \${!isB?'bg-emerald-500':'bg-slate-300'}"><span class="w-4 h-4 bg-white rounded-full absolute top-1 transition-all \${!isB?'left-7':'left-1'}"></span></button></div><div class="mb-4"><div class="flex justify-between text-xs mb-1 font-bold text-slate-500"><span>\${formatBytes(ub)}</span><span>\${lb>5000?formatBytes(lb):'Unl'}</span></div><div class="w-full bg-slate-100 rounded-full h-2"><div class="\${pc} h-2 rounded-full" style="width:\${p}%"></div></div></div><div class="flex justify-between pt-3 border-t"><div class="space-x-1"><button onclick="editKey('\${k.id}','\${rn.replace(/'/g,"\\\\'")}', '\${ed||''}', \${lb})" class="p-2 hover:bg-slate-100 rounded"><i data-lucide="settings-2" class="w-4 h-4"></i></button><button onclick="deleteKey('\${k.id}')" class="p-2 hover:text-red-500 rounded"><i data-lucide="trash-2" class="w-4 h-4"></i></button></div><button onclick="copyKey('\${url}')" class="text-xs font-bold text-slate-500 border px-2 py-1 rounded">Copy</button></div></div>\`;
            } lucide.createIcons();
        }
        async function autoBlockKey(id){try{await fetch(\`\${apiUrl}/access-keys/\${id}/data-limit\`,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({limit:{bytes:1}})});}catch(e){}}
        async function toggleKey(id,isB){try{if(isB)await fetch(\`\${apiUrl}/access-keys/\${id}/data-limit\`,{method:'DELETE'});else await fetch(\`\${apiUrl}/access-keys/\${id}/data-limit\`,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({limit:{bytes:1}})});refreshData();}catch(e){showToast("Error");}}
        async function deleteKey(id){if(!confirm("Delete?"))return;try{await fetch(\`\${apiUrl}/access-keys/\${id}\`,{method:'DELETE'});refreshData();}catch(e){}}
        function copyKey(t){const el=document.createElement('textarea');el.value=t;document.body.appendChild(el);el.select();document.execCommand('copy');document.body.removeChild(el);showToast("Copied");}
        const modal=document.getElementById('modal-overlay');
        function closeModal(){modal.classList.add('hidden');}
        function openCreateModal(){document.getElementById('key-form').reset();document.getElementById('key-id').value='';const d=new Date();d.setDate(d.getDate()+30);document.getElementById('key-expire').value=d.toISOString().split('T')[0];modal.classList.remove('hidden');}
        function editKey(id,name,date,bytes){document.getElementById('key-id').value=id;document.getElementById('key-name').value=name;document.getElementById('key-expire').value=date;if(bytes>5000){if(bytes>=1073741824){document.getElementById('key-limit').value=(bytes/1073741824).toFixed(2);document.getElementById('key-unit').value='GB';}else{document.getElementById('key-limit').value=(bytes/1048576).toFixed(2);document.getElementById('key-unit').value='MB';}}else{document.getElementById('key-limit').value='';}modal.classList.remove('hidden');}
        document.getElementById('key-form').addEventListener('submit',async(e)=>{e.preventDefault();const id=document.getElementById('key-id').value;let name=document.getElementById('key-name').value.trim();const date=document.getElementById('key-expire').value;const lv=parseFloat(document.getElementById('key-limit').value);const u=document.getElementById('key-unit').value;if(date)name+=\` | \${date}\`;try{let tid=id;if(!tid){const r=await fetch(\`\${apiUrl}/access-keys\`,{method:'POST'});const d=await r.json();tid=d.id;}await fetch(\`\${apiUrl}/access-keys/\${tid}/name\`,{method:'PUT',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:\`name=\${encodeURIComponent(name)}\`});if(lv>0){let b=(u==='GB')?Math.floor(lv*1024*1024*1024):Math.floor(lv*1024*1024);await fetch(\`\${apiUrl}/access-keys/\${tid}/data-limit\`,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({limit:{bytes:b}})});}else{await fetch(\`\${apiUrl}/access-keys/\${tid}/data-limit\`,{method:'DELETE'});}closeModal();refreshData();showToast("Saved");}catch(e){showToast("Error");}});
    </script>
</body>
</html>
EOF

# 9. PM2 Setup & Startup
echo -e "${YELLOW}[+] Services များကို စတင်နေပါသည်...${NC}"

# Stop old processes if any
pm2 delete outline-guard 2>/dev/null
pm2 delete outline-web 2>/dev/null

# Start Bot
pm2 start bot.js --name "outline-guard"

# Start Web Server (Port 8080)
pm2 start http-server --name "outline-web" -- -p 8080

# Save PM2 list
pm2 save
pm2 startup

# 10. Firewall Config
echo -e "${YELLOW}[+] Firewall Port 8080 ကို ဖွင့်နေပါသည်...${NC}"
ufw allow 8080/tcp > /dev/null 2>&1

# 11. Final Output
IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   INSTALLATION COMPLETE! (အောင်မြင်ပါသည်)   ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "Web Panel ကို ဝင်ရောက်ရန်:"
echo -e "${YELLOW}http://${IP}:8080${NC}"
echo -e ""
echo -e "Bot Status:"
echo -e "${YELLOW}pm2 logs outline-guard${NC}"
echo -e "${GREEN}==============================================${NC}"
