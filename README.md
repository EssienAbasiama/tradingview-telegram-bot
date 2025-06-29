# 📈 TradingView → Telegram Webhook Alert System

A lightweight **Node.js + Express** webhook server that bridges **TradingView alerts** directly into a **Telegram channel** or private chat. This app is perfect for traders looking to automate real-time notifications like **volume spikes**, **EMA/MA touches**, and **break/retest setups** directly into Telegram — securely and effortlessly.

---

## 🚀 Features

* 📡 **Webhook Listener** — Receives alert payloads from TradingView in JSON format.
* 🧠 **Alert Parser** — Extracts and formats fields like `pair`, `event`, `timeframe`, `timestamp`, and `volume`.
* 📬 **Telegram Messaging** — Sends alerts to a specific Telegram **user** or **private channel** using your bot.
* 🔗 **/start Command Handler** — Responds with a link to your private Telegram channel when a user starts the bot.
* 🔐 **Secure Delivery** — Accepts only valid POST requests from TradingView or Telegram.
* 🌐 **Ngrok Support** — Easily expose your localhost for webhook testing and development.

---

## ⚙️ Technologies Used

| Stack                 | Purpose                                                           |
| --------------------- | ----------------------------------------------------------------- |
| **Node.js + Express** | Web server to handle webhook routes                               |
| **Axios**             | Sends HTTP requests to the Telegram Bot API                       |
| **dotenv**            | Loads environment variables from `.env`                           |
| **Ngrok**             | Makes local dev server publicly accessible (for testing webhooks) |

---

## 🛠 How It Works

### 1️⃣ TradingView Sends an Alert

An alert is sent from TradingView to your public webhook URL:

```
https://<your-ngrok-or-production-domain>/tradingview-webhook
```

Example payload:

```json
{
  "pair": "BTCUSDT",
  "event": "EMA 200 Touch",
  "timeframe": "1H",
  "timestamp": "2024-06-29T13:45:00Z",
  "volume": "54321"
}
```

### 2️⃣ The Server Parses & Sends to Telegram

Your app receives the data and sends a beautifully formatted message:

```
📡 Alert Triggered!

Pair: BTCUSDT  
Event: EMA 200 Touch  
Timeframe: 1H  
Timestamp: June 29, 2024, 1:45 PM UTC  
Volume: 54321
```

### 3️⃣ User Clicks /start in Telegram Bot

When a user sends `/start` to the bot, it replies with a link to your private trading alerts channel:

```
👋 Welcome! Join our trading alerts channel here:
🔗 https://t.me/+RV4t92fD0oFkMDRk
```

---

## 🔐 Example `.env` File

```env
PORT=5000
TELEGRAM_TOKEN=your_telegram_bot_token
CHAT_ID=@your_channel_username_or_user_id
```

> 💡 If you're posting to a **private channel**, make sure your bot is added as an **admin** in the channel.

---

## 📦 Installation & Setup

```bash
git clone https://github.com/your-username/tradingview-telegram-bot.git
cd tradingview-telegram-bot
npm install
```

Create a `.env` file using the template above, then run:

```bash
node index.js
```

To expose your server with **Ngrok**:

```bash
ngrok http 5000
```

---

## ✅ Coming Soon

* [ ] Support for Smart Money Concepts (SMC): BOS / CHoCH logic
* [ ] Multi-timeframe confirmation
* [ ] Scheduled session-based alerts

---

## 🤝 Contributions
