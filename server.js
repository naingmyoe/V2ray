const express = require('express');
const axios = require('axios');
const https = require('https');
const low = require('lowdb');
const FileSync = require('lowdb/adapters/FileSync');
const cors = require('cors');
const os = require('os');
const osu = require('node-os-utils');

const app = express();
app.use(express.json());
app.use(cors());

// Database setup
const adapter = new FileSync('database.json');
const db = low(adapter);
db.defaults({ users: [], settings: {} }).write();

const agent = new https.Agent({ rejectUnauthorized: false });
const getApiUrl = (req) => req.headers['x-outline-api-url'];

// --- System Status API (Like X-UI Dashboard) ---
app.get('/api/status', async (req, res) => {
    const cpu = await osu.cpu.usage();
    const mem = await osu.mem.info();
    
    res.json({
        cpu: cpu,
        mem: mem.usedMemMb / mem.totalMemMb * 100, // RAM %
        uptime: os.uptime(),
        totalMem: mem.totalMemMb,
        usedMem: mem.usedMemMb
    });
});

// --- Outline APIs ---

// 1. Login/Test
app.post('/api/login', async (req, res) => {
    try {
        const response = await axios.get(`${req.body.apiUrl}/server`, { httpsAgent: agent });
        res.json({ success: true, info: response.data });
    } catch (error) {
        res.status(401).json({ success: false });
    }
});

// 2. Get Users (Merged with DB)
app.get('/api/users', async (req, res) => {
    const apiUrl = getApiUrl(req);
    try {
        const response = await axios.get(`${apiUrl}/access-keys`, { httpsAgent: agent });
        const localUsers = db.get('users').value();
        
        // Merge real-time stats with local expiry data
        const merged = response.data.accessKeys.map(key => {
            const local = localUsers.find(u => u.id === key.id);
            return {
                ...key,
                expireDate: local ? local.expireDate : null,
                totalLimit: key.dataLimit ? key.dataLimit.bytes : 0
            };
        });
        res.json(merged);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// 3. Add User
app.post('/api/users', async (req, res) => {
    const apiUrl = getApiUrl(req);
    const { name, limitGB, expireDays } = req.body;
    try {
        // Create Key
        const { data: newKey } = await axios.post(`${apiUrl}/access-keys`, {}, { httpsAgent: agent });
        
        // Rename
        await axios.put(`${apiUrl}/access-keys/${newKey.id}/name`, { name }, { httpsAgent: agent });
        
        // Set Limit
        if (limitGB > 0) {
            const bytes = limitGB * 1024 * 1024 * 1024;
            await axios.put(`${apiUrl}/access-keys/${newKey.id}/data-limit`, { limit: { bytes } }, { httpsAgent: agent });
        }

        // Set Expiry
        if (expireDays > 0) {
            const expireDate = new Date();
            expireDate.setDate(expireDate.getDate() + parseInt(expireDays));
            db.get('users').push({ id: newKey.id, expireDate }).write();
        }
        
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// 4. Delete User
app.delete('/api/users/:id', async (req, res) => {
    const apiUrl = getApiUrl(req);
    try {
        await axios.delete(`${apiUrl}/access-keys/${req.params.id}`, { httpsAgent: agent });
        db.get('users').remove({ id: req.params.id }).write();
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

const PORT = 3000;
app.listen(PORT, () => console.log(`X-UI Style Panel running on port ${PORT}`));
