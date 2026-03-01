const express = require('express');
const router = express.Router();
const mt5Controller = require('../controllers/mt5Controller');

router.get('/commands', (req, res) => {
    if (!mt5Controller || typeof mt5Controller.getCommands !== 'function') {
        console.error('mt5Controller.getCommands missing');
        return res.status(500).send('handler missing');
    }
    return mt5Controller.getCommands(req, res);
});


router.post('/status', (req, res) => {
    if (!mt5Controller || typeof mt5Controller.postStatus !== 'function') {
        console.error('mt5Controller.postStatus missing');
        return res.status(500).send('handler missing');
    }
    return mt5Controller.postStatus(req, res);
});

// Debug: view raw MT5 status log
router.get('/debug/status-log', (req, res) => {
    if (!mt5Controller || typeof mt5Controller.getStatusLog !== 'function') {
        console.error('mt5Controller.getStatusLog missing');
        return res.status(500).send('handler missing');
    }
    return mt5Controller.getStatusLog(req, res);
});

module.exports = router;
