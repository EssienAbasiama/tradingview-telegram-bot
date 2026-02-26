const sessions = {}; // key: chatId -> { section, selectedPair, awaitingInput }

function getSession(chatId) {
    if (!sessions[chatId]) sessions[chatId] = {};
    return sessions[chatId];
}

function setSession(chatId, session) {
    sessions[chatId] = Object.assign(getSession(chatId), session || {});
    return sessions[chatId];
}

function clearSession(chatId) {
    delete sessions[chatId];
}

function updateSession(chatId, patch) {
    return setSession(chatId, Object.assign(getSession(chatId), patch || {}));
}

module.exports = { getSession, setSession, clearSession, updateSession };
