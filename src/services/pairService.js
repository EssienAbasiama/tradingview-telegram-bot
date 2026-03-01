const fs = require('fs');
const path = require('path');
const Pair = require('../models/pairModel');

const pairs = {}; // key: symbol -> Pair
const SYMBOLS_FILE = path.join(__dirname, '..', '..', 'symbols.txt');

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
    // Also clear the persisted symbols file so the EA has no saved active pairs
    try {
        fs.writeFileSync(SYMBOLS_FILE, '');
    } catch (e) {
        console.error('pairService.clearPairs: failed to clear symbols file', e && e.message ? e.message : e);
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
