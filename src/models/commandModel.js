class Command {
    constructor(type, symbol = null, payload = {}, createdBy = null) {
        this.id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        this.type = type; // e.g., 'add_pair','toggle_cross','pause_ea'
        this.symbol = symbol;
        this.payload = payload || {};
        this.status = 'pending';
        this.timestamp = new Date().toISOString();
        this.createdBy = createdBy;
    }
}

module.exports = Command;
