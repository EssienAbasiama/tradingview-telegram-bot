const express = require("express");
const dotenv = require("dotenv");
const axios = require("axios");
const bodyParser = require("body-parser");

dotenv.config();
const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(bodyParser.json());



// === 1. Handle TradingView Webhook ===
app.post("/tradingview-webhook", async (req, res) => {
  const { pair, event, timeframe, timestamp, volume } = req.body;

  const formattedTime = new Date(timestamp).toLocaleString("en-US", {
    timeZone: "UTC",
    year: "numeric",
    month: "long",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });

  const message = `📡 *Alert Triggered!*\n\n*Pair:* ${pair}\n*Event:* ${event}\n*Timeframe:* ${timeframe}\n*Timestamp:* ${formattedTime} UTC\n*Volume:* ${volume}`;

  try {
    await axios.post(
      `https://api.telegram.org/bot${process.env.TELEGRAM_TOKEN}/sendMessage`,
      {
        chat_id: process.env.CHANNEL_CHAT_ID,
        text: message,
        parse_mode: "Markdown",
      }
    );

    console.log("✅ Alert sent to Telegram channel");
    res.status(200).send("OK");
  } catch (error) {
    console.error("❌ Failed to send Telegram message:", error.message);
    res.status(500).send("Failed to send message");
  }
});

// === 2. Handle Bot Commands (/start, etc.) ===
app.post("/telegram-webhook", async (req, res) => {
  const message = req.body.message;

  if (!message) return res.status(400).send("No message found");

  const chatId = message.chat.id;
  const firstName = message.chat.first_name || "friend";
  const text = message.text?.toLowerCase() || "";

  if (text === "/start") {
    const welcomeText = `👋 Hi *${firstName}*!\n\nWelcome to our trading alert system.\nClick below to join our private channel:\n👉 [Join Now](${process.env.CHANNEL_LINK})`;

    try {
      await axios.post(
        `https://api.telegram.org/bot${process.env.TELEGRAM_TOKEN}/sendMessage`,
        {
          chat_id: chatId,
          text: welcomeText,
          parse_mode: "Markdown",
          disable_web_page_preview: true,
        }
      );

      console.log("✅ Sent welcome message");
      res.status(200).send("Welcome sent");
    } catch (err) {
      console.error("❌ Failed to send /start message:", err.message);
      res.status(500).send("Failed to send welcome message");
    }
  } else {
    // Optional: Handle other messages
    res.status(200).send("OK");
  }
});

// === 3. Handle MetaTrader EA Alerts ===
app.post("/meta", async (req, res) => {
const { symbol, signal, timeframe, price, message, timestamp } = req.body;

  const formattedTime = new Date().toLocaleString("en-US", {
    timeZone: "UTC",
    year: "numeric",
    month: "long",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });

  const message =
    `📊 *MT5 Alert Triggered!*\n\n` +
    `*Symbol:* ${symbol}\n` +
    `*Signal:* ${signal}\n` +
    `*Timeframe:* ${timeframe}\n` +
    `*Price:* ${price}\n` +
    `*Time:* ${formattedTime} UTC`;

  try {
    await axios.post(
      `https://api.telegram.org/bot${process.env.TELEGRAM_TOKEN}/sendMessage`,
      {
        chat_id: process.env.CHANNEL_CHAT_ID,
        text: message,
        parse_mode: "Markdown",
      }
    );

    console.log("✅ MT5 alert sent to Telegram");
    res.status(200).send("OK");
  } catch (error) {
    console.error("❌ Failed to send MT5 alert:", error.message);
    res.status(500).send("Failed to send MT5 alert");
  }
});

// === Basic Test Route ===
app.get("/", (req, res) => {
  res.send("🚀 TradingView Webhook + Telegram Bot Webhook Running");
});

// === Start Server ===
app.listen(PORT, () => {
  console.log(`🟢 Server running at http://localhost:${PORT}`);
});
