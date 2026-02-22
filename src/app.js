const express = require('express');
const bodyParser = require('body-parser');
const dotenv = require('dotenv');

dotenv.config();

const app = express();
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Routes
const telegramRoutes = require('./routes/telegramRoutes');
const mt5Routes = require('./routes/mt5Routes');

app.use('/telegram', telegramRoutes);
// Alias to support existing webhook paths that include /api prefix
app.use('/api/telegram', telegramRoutes);
app.use('/api', mt5Routes);

app.get('/', (req, res) => res.send('🚀 Smart MT5 Backend (modular)'));

module.exports = app;
