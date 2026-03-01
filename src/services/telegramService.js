const axios = require('axios');

async function postWithRetry(url, payload, retries = 2) {
    let lastErr = null;
    for (let i = 0; i <= retries; i++) {
        try {
            return await axios.post(url, payload, { timeout: 10000 });
        } catch (e) {
            lastErr = e;
            const code = e && e.code ? e.code : '';
            if (code !== 'ETIMEDOUT' && code !== 'ECONNRESET' && code !== 'EAI_AGAIN') {
                break;
            }
        }
    }
    throw lastErr;
}

async function sendMessage(token, chatId, text, keyboard = null, isReplyKeyboard = false, parseMode = 'Markdown') {
    const payload = { chat_id: chatId, text };
    if (parseMode) payload.parse_mode = parseMode;
    if (keyboard) {
        payload.reply_markup = isReplyKeyboard
            ? { keyboard, resize_keyboard: true, one_time_keyboard: false }
            : { inline_keyboard: keyboard };
    }
    await postWithRetry(`https://api.telegram.org/bot${token}/sendMessage`, payload);
}

async function editMessageText(token, chatId, messageId, text, keyboard = null) {
    const payload = { chat_id: chatId, message_id: messageId, text, parse_mode: 'Markdown' };
    if (keyboard) {
        payload.reply_markup = { inline_keyboard: keyboard };
    }
    await postWithRetry(`https://api.telegram.org/bot${token}/editMessageText`, payload);
}

async function answerCallback(token, callbackId) {
    return postWithRetry(`https://api.telegram.org/bot${token}/answerCallbackQuery`, { callback_query_id: callbackId });
}

module.exports = { sendMessage, editMessageText, answerCallback };
