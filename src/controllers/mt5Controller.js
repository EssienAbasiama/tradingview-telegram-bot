const fs = require('fs');
const path = require('path');
const commandService = require('../services/commandService');
const pairService = require('../services/pairService');
const telegramService = require('../services/telegramService');

const LOG_DIR = path.join(__dirname, '..', '..', 'logs');
const LOG_FILE = path.join(LOG_DIR, 'status.log');

const TOKEN = process.env.TELEGRAM_TOKEN;
const MAIN_CHANNEL = process.env.CHANNEL_CHAT_ID;
const TREND_CHANNEL = process.env.TREND_CHANNEL_CHAT_ID || process.env.TREND_CHANNEL_CHAT_ID || process.env.TREND_CHANNEL_CHAT_ID;
const ADMIN_CHAT = process.env.CHAT_ID;

// Return pending commands for MT5 EA to consume
function getCommands(req, res) {
    const limit = parseInt(req.query.limit || '50', 10);
    const cmds = commandService.getPendingCommands(limit);
    console.log('GET /api/commands returning', cmds.length, 'pending commands');
    return res.json({ commands: cmds });
}

// MT5 posts status updates and alerts here
async function postStatus(req, res) {
    try {
        // Accept many MT5 WebRequest formats: JSON, raw text, x-www-form-urlencoded
        // Normalize into object and add helpful logging for debugging.
        console.log('/api/status incoming, content-type=', req.headers['content-type']);
        let payload = req.body;

        // If body-parser produced a string, try JSON parse or url-decoded JSON
        if (typeof payload === 'string') {
            const raw = payload.trim();
            try {
                payload = JSON.parse(raw);
            } catch (e) {
                const eq = raw.indexOf('=');
                if (eq >= 0) {
                    const candidate = raw.slice(eq + 1);
                    try {
                        payload = JSON.parse(decodeURIComponent(candidate));
                    } catch (err2) {
                        payload = {};
                    }
                } else {
                    payload = {};
                }
            }
        }

        // If body-parser parsed urlencoded form into an object where the JSON string
        // is the sole key (some servers do this when raw JSON is posted with bad headers)
        if (typeof payload === 'object' && payload !== null) {
            const keys = Object.keys(payload);
            if (keys.length === 1 && typeof keys[0] === 'string' && keys[0].trim().startsWith('{')) {
                try { payload = JSON.parse(keys[0]); }
                catch (e) { /* leave as-is */ }
            }
            // common wrappers
            if (payload && typeof payload.body === 'string') {
                try { payload = JSON.parse(payload.body); } catch (e) { /* ignore */ }
            }
            if (payload && typeof payload.payload === 'string') {
                try { payload = JSON.parse(decodeURIComponent(payload.payload)); } catch (e) { /* ignore */ }
            }
        }

        console.log('/api/status payload keys=', payload && typeof payload === 'object' ? Object.keys(payload) : typeof payload);
        // If payload looks empty or missing `type`, try parsing raw body captured by middleware
        if ((typeof payload !== 'object' || payload === null || !payload.type) && req.rawBody) {
            try {
                const maybe = JSON.parse(req.rawBody);
                if (maybe && typeof maybe === 'object' && maybe.type) {
                    payload = maybe;
                    console.log('/api/status parsed payload from rawBody');
                }
            } catch (e) { /* ignore parse errors */ }
        }
        // ensure logs directory
        try {
            if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });
            fs.appendFile(LOG_FILE, new Date().toISOString() + ' ' + JSON.stringify(payload) + '\n', (e) => { if (e) console.error('log write error', e); });
        } catch (e) { console.error('log setup error', e); }
        // Expect { commandId?, type, symbol, result, details }
        if (!payload || !payload.type) return res.status(400).send('Invalid payload');

        // Special handling for symbols list returned by MT5
        // Accept both 'symbols_list' (preferred) and legacy 'get_symbols'
        if ((payload.type || '').toString().toLowerCase() === 'symbols_list' || (payload.type || '').toString().toLowerCase() === 'get_symbols') {
            // mark original command executed
            if (payload.commandId) commandService.markExecuted(payload.commandId);

            // find who requested (createdBy)
            const cmd = payload.commandId ? commandService.getCommandById(payload.commandId) : null;
            const targetChat = (cmd && cmd.createdBy) ? cmd.createdBy : ADMIN_CHAT;

            // payload.symbols may be CSV string or an array
            // Some EAs send symbols in `details` (CSV) — accept both.
            let symbols = [];
            if (Array.isArray(payload.symbols)) symbols = payload.symbols;
            else if (typeof payload.symbols === 'string' && payload.symbols.length) symbols = payload.symbols.split(',');
            else if (typeof payload.details === 'string' && payload.details.length) symbols = payload.details.split(',');

            // sanitize and trim
            symbols = symbols.map(s => (s || '').toString().trim()).filter(s => s.length > 0);
            // filter out placeholder responses like 'symbols sent' or other chatter
            symbols = symbols.filter(s => {
                const lower = s.toLowerCase();
                return (
                    lower !== 'symbols sent' &&
                    lower !== 'ok' &&
                    lower !== 'added symbol' &&
                    lower !== 'symbols'
                );
            });// unique
            symbols = Array.from(new Set(symbols));

            const buttons = symbols.map(s => [{ text: s, callback_data: `add_${s}` }]);

            if (buttons.length === 0) {
                try { await telegramService.sendMessage(TOKEN, targetChat, 'No symbols returned from MT5'); }
                catch (e) { console.error('sendMessage error (no symbols):', e && e.message ? e.message : e); }
                return res.json({ ok: true });
            }

            try {
                await telegramService.sendMessage(TOKEN, targetChat, '📈 Select a pair to add:', buttons);
            } catch (e) {
                console.error('sendMessage error (symbols list):', e && e.message ? e.message : e);
            }

            return res.json({ ok: true });
        }

        // Handle active symbols returned by MT5 (response to get_active_symbols)
        if ((payload.type || '').toString().toLowerCase() === 'active_symbols' || (payload.type || '').toString().toLowerCase() === 'get_active_symbols') {
            if (payload.commandId) commandService.markExecuted(payload.commandId);
            const cmd = payload.commandId ? commandService.getCommandById(payload.commandId) : null;
            const targetChat = (cmd && cmd.createdBy) ? cmd.createdBy : ADMIN_CHAT;

            // payload.result or payload.details may contain CSV or array
            let symbols = [];
            if (Array.isArray(payload.symbols)) symbols = payload.symbols;
            else if (typeof payload.result === 'string' && payload.result.length) symbols = payload.result.split(',');
            else if (typeof payload.details === 'string' && payload.details.length) symbols = payload.details.split(',');

            symbols = symbols.map(s => (s || '').toString().trim()).filter(s => s.length > 0);
            symbols = symbols.filter(s => {
                const lower = s.toLowerCase();
                return (lower !== 'empty' && lower !== 'no active symbols' && lower !== 'ok' && lower !== 'symbols');
            });
            symbols = Array.from(new Set(symbols));

            if (symbols.length === 0) {
                try { await telegramService.sendMessage(TOKEN, targetChat, 'No active symbols reported by MT5'); }
                catch (e) { console.error('sendMessage error (no active symbols):', e && e.message ? e.message : e); }
                return res.json({ ok: true });
            }

            // Ensure pairService knows about them
            for (let i = 0; i < symbols.length; i++) {
                try { pairService.addPair(symbols[i]); } catch (e) { /* ignore duplicates */ }
            }

            const mode = cmd && cmd.payload ? (cmd.payload.mode || 'view') : 'view';
            const buttons = symbols.map(s => {
                if (mode === 'remove') return [{ text: s, callback_data: `remove_${s}` }];
                return [{ text: s, callback_data: `settings|${s}` }];
            });
            try {
                await telegramService.sendMessage(TOKEN, targetChat, `📋 Active Pairs (${symbols.length})\n\nSelect a pair to manage:`, buttons);
            } catch (e) { console.error('sendMessage error (active_symbols):', e && e.message ? e.message : e); }

            return res.json({ ok: true });
        }

        // If this is a command execution confirmation, mark executed
        if (payload.commandId) commandService.markExecuted(payload.commandId);

        // Route messages by type
        const text = `*MT5 Status*\nType: ${payload.type}\nSymbol: ${payload.symbol || '-'}\nResult: ${payload.result || '-'}\nDetails: ${payload.details || ''}`;

        // TREND -> trend channel; CROSS/VOLUME -> main channel; else -> admin
        try {
            const ptype = (payload.type || '').toUpperCase();
            console.log('Routing MT5 status, type=', ptype, 'MAIN_CHANNEL=', MAIN_CHANNEL, 'TREND_CHANNEL=', TREND_CHANNEL, 'ADMIN_CHAT=', ADMIN_CHAT);
            if (ptype.startsWith('TREND')) {
                const target = process.env.TREND_CHANNEL_CHAT_ID || TREND_CHANNEL;
                console.log('Sending TREND message to', target);
                await telegramService.sendMessage(TOKEN, target, text);
            } else if (ptype.includes('CROSS') || ptype.includes('VOLUME')) {
                console.log('Sending CROSS/VOLUME message to', MAIN_CHANNEL);
                await telegramService.sendMessage(TOKEN, MAIN_CHANNEL, text);
            } else {
                console.log('Sending OTHER status message to admin', ADMIN_CHAT);
                await telegramService.sendMessage(TOKEN, ADMIN_CHAT, text);
            }
        } catch (e) {
            console.error('sendMessage error (status):', e && e.message ? e.message : e);
            if (e && e.response && e.response.data) console.error('telegram response data:', e.response.data);
        }

        // If payload requests pair updates (e.g., add/remove) reflect in memory
        if (payload.type === 'add_pair' && payload.symbol) {
            const s = payload.symbol.toString().trim();
            // ignore placeholder/ack messages
            if (!/\b(symbols?|sent|ok|added)\b/i.test(s)) {
                pairService.addPair(s);
            } else {
                console.log('Ignoring add_pair for placeholder symbol:', s);
            }
        }
        if (payload.type === 'remove_pair' && payload.symbol) {
            pairService.removePair(payload.symbol);
        }

        return res.json({ ok: true });
    } catch (err) {
        console.error('MT5 /status error', err.message);
        return res.status(500).send('Error');
    }
}

module.exports = { getCommands, postStatus };

// Debug endpoint implementation
function getStatusLog(req, res) {
    try {
        if (!fs.existsSync(LOG_FILE)) return res.status(404).send('No log file');
        const content = fs.readFileSync(LOG_FILE, 'utf8');
        res.type('text/plain').send(content);
    } catch (e) {
        console.error('getStatusLog error', e);
        res.status(500).send('Error reading log');
    }
}

module.exports = { getCommands, postStatus, getStatusLog, handleMetaAlert };

// Handle MT5 /meta alerts: parse payload, format, and forward to Telegram
async function handleMetaAlert(req, res) {
    try {
        let payload = req.body;
        if (typeof payload === 'string') {
            const raw = payload.trim();
            try { payload = JSON.parse(raw); }
            catch (e) {
                const eq = raw.indexOf('=');
                if (eq >= 0) {
                    const candidate = raw.slice(eq + 1);
                    try { payload = JSON.parse(decodeURIComponent(candidate)); }
                    catch (e2) { payload = {}; }
                } else payload = {};
            }
        }

        if (typeof payload === 'object' && payload !== null) {
            const keys = Object.keys(payload);
            if (keys.length === 1 && typeof keys[0] === 'string' && keys[0].trim().startsWith('{')) {
                try { payload = JSON.parse(keys[0]); } catch (e) { /* ignore */ }
            }
            if (payload && typeof payload.body === 'string') {
                try { payload = JSON.parse(payload.body); } catch (e) { /* ignore */ }
            }
            if (payload && typeof payload.payload === 'string') {
                try { payload = JSON.parse(decodeURIComponent(payload.payload)); } catch (e) { /* ignore */ }
            }
        }

        const symbol = (payload.symbol || payload.sym || '').toString().trim();
        const signal = (payload.signal || payload.type || payload.result || '').toString().trim();
        const timeframe = (payload.timeframe || payload.tf || '').toString().trim();
        const priceRaw = (payload.price || payload.value || payload.p || '');
        const timeRaw = payload.time || payload.timestamp || payload.ts || null;

        if (!symbol || !signal || !timeframe || priceRaw === '')
            return res.status(400).json({ ok: false, error: 'Missing required fields' });

        const price = Number(priceRaw);
        if (!isFinite(price)) return res.status(400).json({ ok: false, error: 'Invalid price' });

        const icons = { 'M1': '🔴', 'M5': '🔵', 'M15': '🟢' };
        const icon = icons[timeframe.toUpperCase()] || '';

        function mapSignal(sig) {
            const s = (sig || '').toString().toUpperCase();
            if (s === 'BULLISH') return 'Bullish';
            if (s === 'BEARISH') return 'Bearish';
            if (s === 'CROSS') return 'EMA/SMA Cross';
            if (s === 'VOLUME_SPIKE') return 'Volume Spike';
            if (s.startsWith('TREND_')) {
                const rest = s.slice(6);
                if (rest === 'BULLISH') return 'Trend Bullish';
                if (rest === 'BEARISH') return 'Trend Bearish';
                // friendly fallback
                return 'Trend ' + rest.charAt(0) + rest.slice(1).toLowerCase();
            }
            return null;
        }

        const trendText = mapSignal(signal);
        if (!trendText) return res.json({ ok: true, ignored: true });

        const formattedPrice = price.toFixed(2);

        // determine time string
        let dt;
        if (timeRaw) {
            const n = Number(timeRaw);
            dt = isFinite(n) ? new Date(n) : new Date(timeRaw);
            if (isNaN(dt.getTime())) dt = new Date();
        } else dt = new Date();
        const formattedTime = dt.toISOString().replace('T', ' ').split('.')[0];

        const message = `📊 *MT5 Alert Triggered!*\n\n*Symbol:* ${symbol}\n*Signal:* ${trendText}\n*Timeframe:* ${icon} ${timeframe}\n*Price:* ${formattedPrice}\n*Time:* ${formattedTime} UTC`;

        // choose token + chat by type
        const isTrend = (signal || '').toString().toUpperCase().startsWith('TREND');
        const targetToken = isTrend ? (process.env.TREND_TELEGRAM_TOKEN || process.env.TREND_TELEGRAM_TOKEN) : (process.env.TELEGRAM_TOKEN || TOKEN);
        const targetChat = isTrend ? (process.env.TREND_CHANNEL_CHAT_ID || TREND_CHANNEL) : (process.env.CHANNEL_CHAT_ID || MAIN_CHANNEL);

        try {
            await telegramService.sendMessage(targetToken, targetChat, message);
            return res.json({ ok: true });
        } catch (e) {
            console.error('handleMetaAlert send error', e && e.message ? e.message : e);
            return res.status(500).json({ ok: false, error: 'send failed' });
        }
    } catch (err) {
        console.error('handleMetaAlert error', err && err.message ? err.message : err);
        return res.status(500).json({ ok: false, error: 'internal error' });
    }
}
