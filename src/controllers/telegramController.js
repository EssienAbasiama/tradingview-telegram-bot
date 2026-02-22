const commandService = require('../services/commandService');
const pairService = require('../services/pairService');
const telegramService = require('../services/telegramService');

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
        if (body.message) {
            const chatId = body.message.chat.id;
            const firstName = body.message.chat.first_name || 'friend';
            const text = body.message.text || '';

            if (text === '/start') {
                const mainMenu = [
                    [{ text: '➕ Add Pair' }, { text: '📊 Active Pairs' }],
                    [{ text: '🛠 Global Controls' }, { text: 'ℹ Help' }],
                ];

                safeSend(TOKEN, chatId, `👋 Hi *${firstName}*\nUse the buttons to manage pairs.`, mainMenu, true);
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
                safeSend(TOKEN, chatId, `✅ Command queued to add ${symbol} (id: ${cmd.id})`);
                return res.sendStatus(200);
            }

            if (text.startsWith('📊 Active Pairs') || text.startsWith('/pairs')) {
                const pairs = pairService.listPairs();
                if (pairs.length === 0) {
                    safeSend(TOKEN, chatId, '⚠ No active pairs.');
                    return res.sendStatus(200);
                }

                const pairButtons = pairs.map(p => [{ text: p.symbol, callback_data: `pair_${p.symbol}` }]);
                safeSend(TOKEN, chatId, '📊 Select Active Pair:', pairButtons);
                return res.sendStatus(200);
            }

            if (text.startsWith('ℹ Help')) {
                safeSend(TOKEN, chatId, `Commands:\n➕ Add Pair <SYM>\n📊 Active Pairs\n🛠 Global Controls`);
                return res.sendStatus(200);
            }
        }

        if (body.callback_query) {
            const callback = body.callback_query;
            const chatId = callback.message.chat.id;
            const data = callback.data;
            try { await telegramService.answerCallback(TOKEN, callback.id); }
            catch (e) { console.error('answerCallback error:', e && e.message ? e.message : e); }

            if (data.startsWith('add_')) {
                const symbol = data.replace('add_', '');
                const cmd = commandService.addCommand('add_pair', symbol, {}, chatId);
                // optionally reflect immediately in backend pair listing
                try { pairService.addPair(symbol); } catch(e){/* ignore */}
                safeSend(TOKEN, chatId, `✅ ${symbol} added (id: ${cmd.id})`);
                return res.sendStatus(200);
            }

            if (data.startsWith('pair_')) {
                const symbol = data.replace('pair_', '');
                const keyboard = [
                    [{ text: 'View Status', callback_data: `status_${symbol}` }],
                    [{ text: 'Toggle Cross', callback_data: `toggle_cross_${symbol}` }],
                    [{ text: 'Toggle Trend', callback_data: `toggle_trend_${symbol}` }],
                    [{ text: 'Toggle Volume', callback_data: `toggle_volume_${symbol}` }],
                    [{ text: 'Remove Pair', callback_data: `remove_${symbol}` }],
                ];
                safeSend(TOKEN, chatId, `Controls for ${symbol}:`, keyboard);
                return res.sendStatus(200);
            }

            if (data.startsWith('status_')) {
                const symbol = data.replace('status_', '');
                const pair = pairService.getPair(symbol);
                if (!pair) {
                    safeSend(TOKEN, chatId, 'Pair not found');
                    return res.sendStatus(200);
                }
                const statusText = `*${symbol}*\nCross: ${pair.crossEnabled}\nTrend: ${pair.trendEnabled}\nVolume: ${pair.volumeEnabled}\nFastMA: ${pair.fastMA}\nSlowMA: ${pair.slowMA}`;
                safeSend(TOKEN, chatId, statusText);
                return res.sendStatus(200);
            }

            // Toggle actions -> create commands
            if (data.startsWith('toggle_')) {
                const [, field, symbol] = data.split('_');
                const cmd = commandService.addCommand(`toggle_${field}`, symbol, {}, chatId);
                safeSend(TOKEN, chatId, `🔄 Queued ${field} toggle for ${symbol} (id: ${cmd.id})`);
                return res.sendStatus(200);
            }

            if (data.startsWith('remove_')) {
                const symbol = data.replace('remove_', '');
                const cmd = commandService.addCommand('remove_pair', symbol, {}, chatId);
                safeSend(TOKEN, chatId, `❌ Queued removal for ${symbol} (id: ${cmd.id})`);
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
