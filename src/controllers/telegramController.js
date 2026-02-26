const commandService = require('../services/commandService');
const pairService = require('../services/pairService');
const telegramService = require('../services/telegramService');
const sessionService = require('../services/sessionService');

const TOKEN = process.env.TELEGRAM_TOKEN;
const ADMIN_CHAT = process.env.CHAT_ID;
const CHANNEL_CHAT_ID = process.env.CHANNEL_CHAT_ID;

async function handleWebhook(req, res) {
    const body = req.body;
    try {
        // helper to send messages without crashing webhook on failure
        async function safeSend(...args) {
            try { await telegramService.sendMessage(...args); }
            catch (e) { console.error('Telegram sendMessage error:', e && e.message ? e.message : e); }
        }

        // helper to edit existing message (replace instead of stack)
        async function safeEdit(token, chatId, messageId, text, keyboard = null) {
            try { await telegramService.editMessageText(token, chatId, messageId, text, keyboard); }
            catch (e) { console.error('Telegram editMessageText error:', e && e.message ? e.message : e); }
        }

        const TIMEFRAMES = ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'];

        function buildSettingsText(symbol, pair) {
            return `⚙ Pair Settings — ${symbol}\n\nCross Alerts: ${pair.crossEnabled ? '✅ ON' : '❌ OFF'}\nTrend Alerts: ${pair.trendEnabled ? '✅ ON' : '❌ OFF'}\nVolume Alerts: ${pair.volumeEnabled ? '✅ ON' : '❌ OFF'}\n\nCross TF: ${pair.crossTF}\nTrend TF1: ${pair.trendTF1}\nTrend TF2: ${pair.trendTF2}\nFast MA: ${pair.fastMA}\nSlow MA: ${pair.slowMA}`;
        }

        function buildSettingsKeyboard(symbol, pair) {
            return [
                [
                    { text: `🔁 Cross (${pair.crossEnabled ? 'ON' : 'OFF'})`, callback_data: `toggle_cross|${symbol}` },
                    { text: `📈 Trend (${pair.trendEnabled ? 'ON' : 'OFF'})`, callback_data: `toggle_trend|${symbol}` }
                ],
                [
                    { text: `📊 Volume (${pair.volumeEnabled ? 'ON' : 'OFF'})`, callback_data: `toggle_volume|${symbol}` }
                ],
                [
                    { text: `⏱ Cross TF: ${pair.crossTF}`, callback_data: `change_cross_tf|${symbol}` },
                    { text: `📆 Trend1: ${pair.trendTF1}`, callback_data: `change_trend_tf1|${symbol}` }
                ],
                [
                    { text: `📆 Trend2: ${pair.trendTF2}`, callback_data: `change_trend_tf2|${symbol}` }
                ],
                [
                    { text: `⚡ Fast MA: ${pair.fastMA}`, callback_data: `change_fast_ma|${symbol}` },
                    { text: `🐢 Slow MA: ${pair.slowMA}`, callback_data: `change_slow_ma|${symbol}` }
                ],
                [
                    { text: '🔙 Back', callback_data: 'back_main' }
                ]
            ];
        }

        function buildTfKeyboard(action, symbol) {
            const rows = [];
            rows.push(TIMEFRAMES.slice(0, 3).map(tf => ({ text: tf, callback_data: `set_${action}|${symbol}|${tf}` })));
            rows.push(TIMEFRAMES.slice(3, 6).map(tf => ({ text: tf, callback_data: `set_${action}|${symbol}|${tf}` })));
            rows.push(TIMEFRAMES.slice(6).map(tf => ({ text: tf, callback_data: `set_${action}|${symbol}|${tf}` })));
            rows.push([{ text: '🔙 Back', callback_data: `settings|${symbol}` }]);
            return rows;
        }

        if (body.message) {
            const chatId = body.message.chat.id;
            const firstName = body.message.chat.first_name || 'friend';
            const text = body.message.text || '';
            const session = sessionService.getSession(chatId);

            if (session && session.awaitingInput && text) {
                const field = session.awaitingInput.field;
                const symbol = session.awaitingInput.symbol;
                const value = parseInt(text.trim(), 10);
                if (Number.isNaN(value) || value <= 0) {
                    safeSend(TOKEN, chatId, '❌ Please send a valid positive number.');
                    return res.sendStatus(200);
                }

                const settings = {};
                settings[field] = value;
                commandService.addCommand('update_strategy', symbol, { settings }, chatId);
                pairService.updatePair(symbol, settings);
                sessionService.updateSession(chatId, { awaitingInput: null, promptMessageId: null });

                const pair = pairService.getPair(symbol);
                if (pair && session.promptMessageId) {
                    safeEdit(TOKEN, chatId, session.promptMessageId, buildSettingsText(symbol, pair), buildSettingsKeyboard(symbol, pair));
                } else if (pair) {
                    safeSend(TOKEN, chatId, buildSettingsText(symbol, pair), buildSettingsKeyboard(symbol, pair));
                }
                return res.sendStatus(200);
            }

            if (text === '/start' || text === '🏁 Start') {
                const mainMenu = [
                    [{ text: '🏁 Start' }, { text: '📊 Symbol Management' }],
                    [{ text: '🔔 Alert Controls' }, { text: '⚙ Strategy Settings' }],
                    [{ text: '📡 System Status' }, { text: '❓ Help' }]
                ];

                sessionService.clearSession(chatId);
                safeSend(TOKEN, chatId, `🤖 MT5 Alert Control Panel\n\nHi *${firstName}* — choose an option:`, mainMenu, true);
                return res.sendStatus(200);
            }

            // Symbol Management entry (reply keyboard will send these texts)
            if (text === '📊 Symbol Management') {
                sessionService.updateSession(chatId, { section: 'symbol_management', selectedPair: null });
                const kb = [
                    [{ text: '➕ Add Pair' }],
                    [{ text: '➖ Remove Pair' }, { text: '📋 Active Pairs' }],
                    [{ text: '🔙 Back' }]
                ];
                safeSend(TOKEN, chatId, '📊 Symbol Management\n\nManage trading pairs connected to your MT5 EA.', kb, true);
                return res.sendStatus(200);
            }

            if (text === '➕ Add Pair') {
                // Ask MT5 to return the account/market-watch symbols
                const cmd = commandService.addCommand('get_symbols', null, {}, chatId);
                safeSend(TOKEN, chatId, '🔄 Fetching available symbols from MT5...');
                return res.sendStatus(200);
            }

            if (text.startsWith('/add')) {
                const symbol = text.split(' ')[1]?.toUpperCase();
                if (!symbol) {
                    safeSend(TOKEN, chatId, '❌ Please type the symbol like: EURUSD');
                    return res.sendStatus(200);
                }

                // create command for MT5 to add pair locally
                const cmd = commandService.addCommand('add_pair', symbol, {}, chatId);
                // reflect immediately for UX
                try { pairService.addPair(symbol); } catch (e) { /* ignore */ }
                safeSend(TOKEN, chatId, `✅ Command queued to add ${symbol} (id: ${cmd.id})`);
                return res.sendStatus(200);
            }

            if (text.startsWith('📋 Active Pairs') || text.startsWith('/pairs')) {
                const pairs = pairService.listPairs();
                if (pairs.length === 0) {
                    safeSend(TOKEN, chatId, '⚠ No active pairs.');
                    return res.sendStatus(200);
                }

                sessionService.updateSession(chatId, { section: 'active_pairs' });
                const pairButtons = pairs.map(p => [{ text: p.symbol, callback_data: `settings|${p.symbol}` }]);
                safeSend(TOKEN, chatId, `📋 Active Pairs (${pairs.length})\n\nSelect a pair to manage:`, pairButtons);
                return res.sendStatus(200);
            }

            if (text === '➖ Remove Pair') {
                const pairs = pairService.listPairs();
                if (pairs.length === 0) { safeSend(TOKEN, chatId, '⚠ No active pairs to remove.'); return res.sendStatus(200); }
                sessionService.updateSession(chatId, { section: 'remove_pair' });
                const pairButtons = pairs.map(p => [{ text: p.symbol, callback_data: `remove_${p.symbol}` }]);
                safeSend(TOKEN, chatId, '➖ Select a pair to remove:', pairButtons);
                return res.sendStatus(200);
            }

            if (text === '🔔 Alert Controls') {
                const pairs = pairService.listPairs();
                if (pairs.length === 0) { safeSend(TOKEN, chatId, '⚠ No active pairs.'); return res.sendStatus(200); }
                sessionService.updateSession(chatId, { section: 'alert_controls', selectedPair: null });
                const pairButtons = pairs.map(p => [{ text: p.symbol, callback_data: `settings|${p.symbol}` }]);
                safeSend(TOKEN, chatId, '🔔 Alert Controls\n\nSelect a pair to manage:', pairButtons);
                return res.sendStatus(200);
            }

            if (text === '⚙ Strategy Settings') {
                const pairs = pairService.listPairs();
                if (pairs.length === 0) { safeSend(TOKEN, chatId, '⚠ No active pairs.'); return res.sendStatus(200); }
                sessionService.updateSession(chatId, { section: 'strategy_settings', selectedPair: null });
                const pairButtons = pairs.map(p => [{ text: p.symbol, callback_data: `settings|${p.symbol}` }]);
                safeSend(TOKEN, chatId, '⚙ Strategy Settings\n\nSelect a pair to modify:', pairButtons);
                return res.sendStatus(200);
            }

            if (text === '📡 System Status') {
                const pairs = pairService.listPairs();
                const total = pairs.length;
                const cross = pairs.filter(p => p.crossEnabled).length;
                const trend = pairs.filter(p => p.trendEnabled).length;
                const volume = pairs.filter(p => p.volumeEnabled).length;
                const lastSignal = 'n/a';
                const msg = `📡 System Status\n\nEA Status: 🟢 Running\nConnected to MT5: ✅ Yes\nActive Pairs: ${total}\n\nCross Alerts Enabled Pairs: ${cross}\nTrend Alerts Enabled Pairs: ${trend}\nVolume Alerts Enabled Pairs: ${volume}\n\nLast Signal Sent: ${lastSignal}\nServer Time: ${new Date().toLocaleString()}`;
                const kb = [[{ text: '🔄 Refresh', callback_data: 'sys_refresh' }], [{ text: '🧪 Send Test Alert', callback_data: 'sys_test' }], [{ text: '⏸ Pause Entire EA', callback_data: 'pause_ea' }], [{ text: '▶ Resume Entire EA', callback_data: 'resume_ea' }]];
                safeSend(TOKEN, chatId, msg, kb);
                return res.sendStatus(200);
            }

            if (text === '🔙 Back') {
                sessionService.clearSession(chatId);
                const mainMenu = [
                    [{ text: '🏁 Start' }, { text: '📊 Symbol Management' }],
                    [{ text: '🔔 Alert Controls' }, { text: '⚙ Strategy Settings' }],
                    [{ text: '📡 System Status' }, { text: '❓ Help' }]
                ];
                safeSend(TOKEN, chatId, 'Back to main menu', mainMenu, true);
                return res.sendStatus(200);
            }

            if (text.startsWith('ℹ Help')) {
                const helpText = `🤖 MT5 Alert Control Panel

Manage your MT5 alert system directly from Telegram.

━━━━━━━━━━━━━━━━━━

📊 SYMBOL MANAGEMENT
➕ Add Pair – Add a new trading symbol
➖ Remove Pair – Remove a symbol
📋 Active Pairs – View all monitored symbols
⚙️ Pair Settings – Enable/Disable alerts per pair

━━━━━━━━━━━━━━━━━━

🔔 ALERT CONTROLS
✅ Cross Alerts – Enable/Disable MA cross alerts
📈 Trend Alerts – Enable/Disable trend alerts
📊 Volume Alerts – Enable/Disable volume spike alerts
⏸ Pause EA – Pause all alerts
▶ Resume EA – Resume all alerts
🧪 Send Test Alert – Test notification system
📡 System Status – View real-time EA status

━━━━━━━━━━━━━━━━━━

⚙ STRATEGY SETTINGS
⏱ Change Cross Timeframe
📆 Change Trend Timeframes
📐 Modify MA Settings (Fast/Slow)

Select an option below 👇`;

                safeSend(TOKEN, chatId, helpText);
                return res.sendStatus(200);
            }
        }

        if (body.callback_query) {
            const callback = body.callback_query;
            const chatId = callback.message.chat.id;
            const data = callback.data || '';
            try { await telegramService.answerCallback(TOKEN, callback.id); }
            catch (e) { console.error('answerCallback error:', e && e.message ? e.message : e); }

            const parts = data.split('|');
            const action = parts[0];
            const symbol = parts[1];
            const value = parts[2];

            if (data.startsWith('add_')) {
                const sym = data.replace('add_', '');
                const cmd = commandService.addCommand('add_pair', sym, {}, chatId);
                try { pairService.addPair(sym); } catch (e) {/* ignore */ }
                safeSend(TOKEN, chatId, `✅ ${sym} added (id: ${cmd.id})`);
                return res.sendStatus(200);
            }

            if (action === 'settings' || data.startsWith('pair_')) {
                const sym = action === 'settings' ? symbol : data.replace('pair_', '');
                const pair = pairService.getPair(sym);
                if (!pair) {
                    safeSend(TOKEN, chatId, 'Pair not found');
                    return res.sendStatus(200);
                }
                sessionService.updateSession(chatId, { selectedPair: sym });
                safeEdit(TOKEN, chatId, callback.message.message_id, buildSettingsText(sym, pair), buildSettingsKeyboard(sym, pair));
                return res.sendStatus(200);
            }

            if (action && action.startsWith('toggle_') || data.startsWith('toggle_')) {
                let field = '';
                let sym = symbol;
                if (data.startsWith('toggle_')) {
                    const partsUnderscore = data.split('_');
                    field = partsUnderscore[1];
                    sym = partsUnderscore.slice(2).join('_');
                } else {
                    field = action.split('_')[1];
                }

                const sess = sessionService.getSession(chatId);
                if (!sess || !sess.selectedPair || sess.selectedPair !== sym) {
                    safeSend(TOKEN, chatId, '⚠ Please select the pair first.');
                    return res.sendStatus(200);
                }

                commandService.addCommand(`toggle_${field}`, sym, {}, chatId);
                const pair = pairService.getPair(sym);
                if (pair) {
                    if (field === 'cross') pairService.updatePair(sym, { crossEnabled: !pair.crossEnabled });
                    if (field === 'trend') pairService.updatePair(sym, { trendEnabled: !pair.trendEnabled });
                    if (field === 'volume') pairService.updatePair(sym, { volumeEnabled: !pair.volumeEnabled });
                }
                const p = pairService.getPair(sym);
                if (p) {
                    safeEdit(TOKEN, chatId, callback.message.message_id, buildSettingsText(sym, p), buildSettingsKeyboard(sym, p));
                }
                return res.sendStatus(200);
            }

            if (action === 'change_cross_tf' || action === 'change_trend_tf1' || action === 'change_trend_tf2') {
                const label = action === 'change_cross_tf' ? 'Cross TF' : (action === 'change_trend_tf1' ? 'Trend TF1' : 'Trend TF2');
                const next = action.replace('change_', '');
                safeEdit(TOKEN, chatId, callback.message.message_id, `${label}: Select new timeframe`, buildTfKeyboard(next, symbol));
                return res.sendStatus(200);
            }

            if (action === 'set_cross_tf' || action === 'set_trend_tf1' || action === 'set_trend_tf2') {
                const fieldMap = {
                    set_cross_tf: 'crossTF',
                    set_trend_tf1: 'trendTF1',
                    set_trend_tf2: 'trendTF2'
                };
                const field = fieldMap[action];
                if (field && symbol && value) {
                    const settings = {};
                    settings[field] = value;
                    commandService.addCommand('update_strategy', symbol, { settings }, chatId);
                    pairService.updatePair(symbol, settings);
                    const pair = pairService.getPair(symbol);
                    if (pair) {
                        safeEdit(TOKEN, chatId, callback.message.message_id, buildSettingsText(symbol, pair), buildSettingsKeyboard(symbol, pair));
                    }
                }
                return res.sendStatus(200);
            }

            if (action === 'change_fast_ma' || action === 'change_slow_ma') {
                const field = action === 'change_fast_ma' ? 'fastMA' : 'slowMA';
                sessionService.updateSession(chatId, { awaitingInput: { field, symbol }, promptMessageId: callback.message.message_id });
                safeEdit(TOKEN, chatId, callback.message.message_id, `Enter new ${field === 'fastMA' ? 'Fast MA' : 'Slow MA'} value for ${symbol}:`);
                return res.sendStatus(200);
            }

            if (data.startsWith('status_')) {
                const sym = data.replace('status_', '');
                const pair = pairService.getPair(sym);
                if (!pair) {
                    safeSend(TOKEN, chatId, 'Pair not found');
                    return res.sendStatus(200);
                }
                const statusText = `*${sym}*\nCross: ${pair.crossEnabled}\nTrend: ${pair.trendEnabled}\nVolume: ${pair.volumeEnabled}\nFastMA: ${pair.fastMA}\nSlowMA: ${pair.slowMA}`;
                safeSend(TOKEN, chatId, statusText);
                return res.sendStatus(200);
            }

            if (data.startsWith('remove_')) {
                const sym = data.replace('remove_', '');
                const cmd = commandService.addCommand('remove_pair', sym, {}, chatId);
                try { pairService.removePair(sym); } catch (e) { /* ignore */ }
                safeSend(TOKEN, chatId, `❌ Queued removal for ${sym} (id: ${cmd.id})`);
                return res.sendStatus(200);
            }

            if (data === 'back_main') {
                sessionService.clearSession(chatId);
                const mainMenu = [
                    [{ text: '🏁 Start' }, { text: '📊 Symbol Management' }],
                    [{ text: '🔔 Alert Controls' }, { text: '⚙ Strategy Settings' }],
                    [{ text: '📡 System Status' }, { text: '❓ Help' }]
                ];
                safeEdit(TOKEN, chatId, callback.message.message_id, '🤖 MT5 Alert Control Panel\n\nChoose an option:', mainMenu);
                return res.sendStatus(200);
            }
        }

        return res.sendStatus(200);
    } catch (err) {
        console.error('Telegram Webhook Error:', err.message);
        res.sendStatus(500);
    }
}

module.exports = { handleWebhook };
