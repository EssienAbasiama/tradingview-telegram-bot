const commandService = require('../services/commandService');
const pairService = require('../services/pairService');
const telegramService = require('../services/telegramService');

const TOKEN = process.env.TELEGRAM_TOKEN;
const MAIN_CHANNEL = process.env.CHANNEL_CHAT_ID;
const TREND_CHANNEL = process.env.TREND_CHANNEL_CHAT_ID || process.env.TREND_CHANNEL_CHAT_ID || process.env.TREND_CHANNEL_CHAT_ID;
const ADMIN_CHAT = process.env.CHAT_ID;

// Return pending commands for MT5 EA to consume
function getCommands(req, res) {
    const limit = parseInt(req.query.limit || '50', 10);
    const cmds = commandService.getPendingCommands(limit);
    return res.json({ commands: cmds });
}

// MT5 posts status updates and alerts here
async function postStatus(req, res) {
    try {
        const payload = req.body;
        // Expect { commandId?, type, symbol, result, details }
        if (!payload || !payload.type) return res.status(400).send('Invalid payload');

        // Special handling for symbols list returned by MT5
        if (payload.type === 'symbols_list') {
            // mark original command executed
            if (payload.commandId) commandService.markExecuted(payload.commandId);

            // find who requested (createdBy)
            const cmd = payload.commandId ? commandService.getCommandById(payload.commandId) : null;
            const targetChat = (cmd && cmd.createdBy) ? cmd.createdBy : ADMIN_CHAT;

            // payload.symbols may be CSV string or an array
            let symbols = [];
            if (Array.isArray(payload.symbols)) symbols = payload.symbols;
            else if (typeof payload.symbols === 'string' && payload.symbols.length) symbols = payload.symbols.split(',');

            const buttons = symbols.map(s => [{ text: s, callback_data: `add_${s}` }]);

            if (buttons.length === 0) {
                await telegramService.sendMessage(TOKEN, targetChat, 'No symbols returned from MT5');
                return res.json({ ok: true });
            }

            await telegramService.sendMessage(TOKEN, targetChat, '📈 Select a pair to add:', buttons);
            return res.json({ ok: true });
        }

        // If this is a command execution confirmation, mark executed
        if (payload.commandId) commandService.markExecuted(payload.commandId);

        // Route messages by type
        const text = `*MT5 Status*\nType: ${payload.type}\nSymbol: ${payload.symbol || '-'}\nResult: ${payload.result || '-'}\nDetails: ${payload.details || ''}`;

        // TREND -> trend channel; CROSS/VOLUME -> main channel; else -> admin
        if ((payload.type || '').toUpperCase().startsWith('TREND')) {
            await telegramService.sendMessage(TOKEN, process.env.TREND_CHANNEL_CHAT_ID || TREND_CHANNEL, text);
        } else if ((payload.type || '').toUpperCase().includes('CROSS') || (payload.type || '').toUpperCase().includes('VOLUME')) {
            await telegramService.sendMessage(TOKEN, MAIN_CHANNEL, text);
        } else {
            await telegramService.sendMessage(TOKEN, ADMIN_CHAT, text);
        }

        // If payload requests pair updates (e.g., add/remove) reflect in memory
        if (payload.type === 'add_pair' && payload.symbol) {
            pairService.addPair(payload.symbol);
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
