const express = require('express');
const bodyParser = require('body-parser');
const dotenv = require('dotenv');

dotenv.config();

const app = express();
// Some MT5 WebRequest clients send JSON with Content-Type: application/x-www-form-urlencoded
// Accept the raw text for that content-type and attempt to parse it in the controller.
app.use(bodyParser.text({ type: 'application/x-www-form-urlencoded', limit: '1mb' }));
// capture raw body for robust parsing in controllers
app.use(bodyParser.json({ verify: (req, res, buf) => { req.rawBody = buf && buf.toString ? buf.toString() : ''; } }));
app.use(bodyParser.urlencoded({ extended: true, verify: (req, res, buf) => { req.rawBody = buf && buf.toString ? buf.toString() : req.rawBody || ''; } }));

// Routes
const telegramRoutes = require('./routes/telegramRoutes');
const mt5Routes = require('./routes/mt5Routes');

app.use('/telegram', telegramRoutes);
// Alias to support existing webhook paths that include /api prefix
app.use('/api/telegram', telegramRoutes);
app.use('/api', mt5Routes);

app.get('/', (req, res) => res.send('🚀 Smart MT5 Backend (modular)'));

module.exports = app;
