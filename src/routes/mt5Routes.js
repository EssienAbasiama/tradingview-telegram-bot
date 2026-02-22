const express = require('express');
const router = express.Router();
const mt5Controller = require('../controllers/mt5Controller');

router.get('/commands', mt5Controller.getCommands);
router.post('/status', mt5Controller.postStatus);

module.exports = router;
