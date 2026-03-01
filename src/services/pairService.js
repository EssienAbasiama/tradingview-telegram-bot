const Pair = require('../models/pairModel');

const pairs = {}; // key: symbol -> Pair

function addPair(symbol) {
    symbol = symbol.toUpperCase();
    if (pairs[symbol]) return pairs[symbol];
    const p = new Pair(symbol);
    pairs[symbol] = p;
    return p;
}

function removePair(symbol) {
    symbol = symbol.toUpperCase();
    delete pairs[symbol];
}

function getPair(symbol) {
    return pairs[symbol?.toUpperCase()] || null;
}

function listPairs() {
    return Object.values(pairs);
}

function clearPairs() {
    const symbols = Object.keys(pairs);
    for (const symbol of symbols) {
        delete pairs[symbol];
    }
    return symbols.length;
}

function updatePair(symbol, changes) {
    const p = getPair(symbol);
    if (!p) return null;
    Object.assign(p, changes);
    return p;
}

module.exports = { addPair, removePair, getPair, listPairs, clearPairs, updatePair };
