const axios = require('axios');

async function sendMessage(token, chatId, text, keyboard = null, isReplyKeyboard = false) {
    const payload = { chat_id: chatId, text, parse_mode: 'Markdown' };
    if (keyboard) {
        payload.reply_markup = isReplyKeyboard
            ? { keyboard, resize_keyboard: true, one_time_keyboard: false }
            : { inline_keyboard: keyboard };
    }
    await axios.post(`https://api.telegram.org/bot${token}/sendMessage`, payload);
}

async function answerCallback(token, callbackId) {
    return axios.post(`https://api.telegram.org/bot${token}/answerCallbackQuery`, { callback_query_id: callbackId });
}

module.exports = { sendMessage, answerCallback };
