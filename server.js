const express = require("express");
const dotenv = require("dotenv");
const axios = require("axios");
const bodyParser = require("body-parser");

dotenv.config();
const app = express();
const PORT = process.env.PORT || 5000;

app.use("/tradingview-webhook", bodyParser.json());
app.use("/telegram-webhook", bodyParser.json());
app.use("/meta", bodyParser.text({ type: "*/*" }));

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

app.post("/trend-webhook", async (req, res) => {
  const message = req.body.message;
  if (!message) return res.status(400).send("No message found");

  const chatId = message.chat.id;
  const firstName = message.chat.first_name || "friend";
  const text = message.text?.toLowerCase() || "";

  if (text === "/start") {
    const welcomeText =
      `👋 Hi *${firstName}*!\n\n` +
      `Welcome to the *Trend Signals Bot*.\n\n` +
      `👉 Join the private Trend Channel:\n` +
      `${process.env.TREND_CHANNEL_LINK}`;

    try {
      await axios.post(
        `https://api.telegram.org/bot${process.env.TREND_TELEGRAM_TOKEN}/sendMessage`,
        {
          chat_id: chatId,
          text: welcomeText,
          parse_mode: "Markdown",
          disable_web_page_preview: true,
        }
      );
      console.log("✅ Trend welcome message sent");
      return res.status(200).send("Trend Welcome sent");
    } catch (err) {
      console.error("❌ Failed to send Trend /start message:", err.message);
      return res.status(500).send("Failed to send trend welcome");
    }
  }

  res.status(200).send("OK");
});

app.post("/meta", async (req, res) => {
  try {
    console.log("🟢 Raw MT5 body:", req.body);

    const payload =
      typeof req.body === "string" ? JSON.parse(req.body) : req.body;
    const { symbol, signal, timeframe, price } = payload;

    const formattedPrice = parseFloat(price).toFixed(2);
    const formattedTime = new Date().toLocaleString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
    });

    let icon = "";
    if (timeframe === "M1") icon = "🔴";
    else if (timeframe === "M5") icon = "🔵";
    else if (timeframe === "M15") icon = "🟢";

    // Map signal to display text
    let trendText = "";
    if (signal.includes("BULLISH")) trendText = "Bullish";
    else if (signal.includes("BEARISH")) trendText = "Bearish";
    else if (signal.includes("CROSS")) trendText = "EMA/SMA Cross";
    else if (signal.includes("VOLUME_SPIKE")) trendText = "Volume Spike";
    else if (signal.includes("TREND"))
      trendText = signal.replace("TREND_", "Trend ");
    else return res.status(200).send("Ignored non-trend signal");

    const message =
      `📊 *MT5 Alert Triggered!*\n\n` +
      `*Symbol:* ${symbol}\n` +
      `*Signal:* ${trendText}\n` +
      `*Timeframe:* ${icon} ${timeframe}\n` +
      `*Price:* ${formattedPrice}\n` +
      `*Time:* ${formattedTime} UTC`;

    console.log("Formatted MT5 message:", message);

    // Send TREND signals to the TREND channel
    if (signal.includes("TREND")) {
      await axios.post(
        `https://api.telegram.org/bot${process.env.TREND_TELEGRAM_TOKEN}/sendMessage`,
        {
          chat_id: process.env.TREND_CHANNEL_CHAT_ID,
          text: message,
          parse_mode: "Markdown",
        }
      );
      console.log("📈 MT5 Trend Alert sent → TREND CHANNEL");
    } else {
      // Send other signals (BULLISH, BEARISH, CROSS) to the main channel
      await axios.post(
        `https://api.telegram.org/bot${process.env.TELEGRAM_TOKEN}/sendMessage`,
        {
          chat_id: process.env.CHANNEL_CHAT_ID,
          text: message,
          parse_mode: "Markdown",
        }
      );
      console.log("📨 MT5 Normal Alert sent → MAIN CHANNEL");
    }

    res.status(200).send("OK");
  } catch (err) {
    console.error("❌ Failed to process MT5 alert:", err.message);
    res.status(400).send("Invalid MT5 payload");
  }
});

app.get("/", (req, res) => {
  res.send("🚀 TradingView Webhook + Telegram Bot Webhook Running");
});

app.listen(PORT, () => {
  console.log(`🟢 Server running at http://localhost:${PORT}`);
});
