const express = require('express');
const bodyParser = require('body-parser');
const dotenv = require('dotenv');

dotenv.config();

const app = express();
// Parse JSON and urlencoded first (with a verify hook that captures the raw bytes)
app.use(bodyParser.json({ limit: '1mb', verify: (req, res, buf) => { req.rawBody = buf && buf.toString ? buf.toString() : ''; } }));
app.use(bodyParser.urlencoded({ extended: true, limit: '1mb', verify: (req, res, buf) => { req.rawBody = buf && buf.toString ? buf.toString() : req.rawBody || ''; } }));
// For any other content-type (text/plain, custom MT5 wrappers) capture raw text so controllers can attempt parsing
// Don't override `req.body` for application/json — capture raw body only when not already set
app.use((req, res, next) => {
    if (req.rawBody && req.rawBody.length) return next();
    let data = '';
    req.setEncoding && req.setEncoding('utf8');
    req.on('data', chunk => { data += chunk; });
    req.on('end', () => { req.rawBody = req.rawBody || data; next(); });
    req.on('error', () => next());
});

// Routes
const telegramRoutes = require('./routes/telegramRoutes');
const mt5Routes = require('./routes/mt5Routes');

app.use('/telegram', telegramRoutes);
// Alias to support existing webhook paths that include /api prefix
app.use('/api/telegram', telegramRoutes);
app.use('/api', mt5Routes);

app.get('/', (req, res) => res.send('🚀 Smart MT5 Backend (modular)'));

module.exports = app;
