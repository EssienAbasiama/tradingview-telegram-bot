const Command = require('../models/commandModel');

const commands = []; // in-memory queue

function addCommand(type, symbol = null, payload = {}, createdBy = null) {
    const cmd = new Command(type, symbol, payload, createdBy);
    commands.push(cmd);
    return cmd;
}

function getPendingCommands(limit = 50) {
    return commands.filter(c => c.status === 'pending').slice(0, limit);
}

function markExecuted(id) {
    const cmd = commands.find(c => c.id === id);
    if (!cmd) return false;
    cmd.status = 'executed';
    cmd.executedAt = new Date().toISOString();
    return true;
}

function findAndRemove(id) {
    const idx = commands.findIndex(c => c.id === id);
    if (idx >= 0) commands.splice(idx, 1);
}

function getCommandById(id) {
    return commands.find(c => c.id === id) || null;
}

module.exports = { addCommand, getPendingCommands, markExecuted, findAndRemove, getCommandById };
