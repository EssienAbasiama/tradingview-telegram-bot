// Lightweight license service stub — expandable for production
const licenses = {}; // accountNumber -> { expiresAt, boundAccount }

function validateLicense(accountNumber) {
    const rec = licenses[accountNumber];
    if (!rec) return { valid: false, reason: 'No license' };
    if (new Date(rec.expiresAt) < new Date()) return { valid: false, reason: 'Expired' };
    return { valid: true, record: rec };
}

function bindAccount(accountNumber, data) {
    licenses[accountNumber] = Object.assign({}, data);
    return licenses[accountNumber];
}

module.exports = { validateLicense, bindAccount };
