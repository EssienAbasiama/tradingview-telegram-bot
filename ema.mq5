//+------------------------------------------------------------------+
//|                                    EMA_Meta_Alerts.mq5           |
//|                         Author: Essien Abasiama © 2025 Abasiama  |
//+------------------------------------------------------------------+
#property copyright "Essien Abasiama © 2025 Abasiama"
#property link      "https://www.mql5.com"
#property version   "1.02"
#property strict

input int Fast_MA = 9;    // Fast EMA
input int Slow_MA = 21;   // Slow EMA

// Timeframes we want to monitor
ENUM_TIMEFRAMES TFs[3] = { PERIOD_M5, PERIOD_M15, PERIOD_H1 };

// Signal memory to avoid duplicate alerts
bool sentLong[3];
bool sentShort[3];

// Backend URL (Render server endpoint)
string BASE_URL = "https://tradingview-telegram-bot-3f68.onrender.com/meta";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("✅ EMA Meta Alert EA Initialized for ", _Symbol);
   ArrayInitialize(sentLong, false);
   ArrayInitialize(sentShort, false);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   for(int i=0; i<ArraySize(TFs); i++)
     {
      ENUM_TIMEFRAMES tf = TFs[i];
      string tfName = TimeframeToString(tf);

      // --- get EMA values ---
      double maFast[2], maSlow[2];
      if(CopyBuffer(iMA(_Symbol, tf, Fast_MA, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 2, maFast) < 2) continue;
      if(CopyBuffer(iMA(_Symbol, tf, Slow_MA, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 2, maSlow) < 2) continue;

      // Current and previous
      double fastNow = maFast[0];
      double fastPrev = maFast[1];
      double slowNow = maSlow[0];
      double slowPrev = maSlow[1];

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // LONG signal
      if(fastNow > slowNow && fastPrev <= slowPrev && !sentLong[i])
        {
         string msg = "📈 LONG EMA Cross on " + _Symbol +
                      "\n⏱ Timeframe: " + tfName +
                      "\nPrice: " + DoubleToString(bid,_Digits);
         SendToBackend(_Symbol, "LONG", tfName, bid, msg);
         sentLong[i] = true;
         sentShort[i] = false;
        }

      // SHORT signal
      if(fastNow < slowNow && fastPrev >= slowPrev && !sentShort[i])
        {
         string msg = "📉 SHORT EMA Cross on " + _Symbol +
                      "\n⏱ Timeframe: " + tfName +
                      "\nPrice: " + DoubleToString(bid,_Digits);
         SendToBackend(_Symbol, "SHORT", tfName, bid, msg);
         sentShort[i] = true;
         sentLong[i] = false;
        }
     }
  }

//+------------------------------------------------------------------+
//| Send Alert to Node.js Backend                                    |
//+------------------------------------------------------------------+
void SendToBackend(string symbol, string signal, string timeframe, double price, string message)
  {
   string json = "{"
                 +"\"symbol\":\""+symbol+"\","
                 +"\"signal\":\""+signal+"\","
                 +"\"timeframe\":\""+timeframe+"\","
                 +"\"timestamp\":\""+(string)TimeCurrent()+"\","
                 +"\"price\":\""+DoubleToString(price,_Digits)+"\","
                 +"\"message\":\""+message+"\""
                 +"}";

   uchar post[];
   StringToCharArray(json, post, 0, WHOLE_ARRAY, CP_UTF8);

   uchar result[];
   string headers = "Content-Type: application/json\r\n";
   int res = WebRequest("POST", BASE_URL, headers, 5000, post, result, headers);

   if(res == -1)
     Print("❌ WebRequest failed: ", GetLastError());
   else
     Print("✅ Sent alert to backend: ", message);
  }

//+------------------------------------------------------------------+
//| Helper: Convert timeframe to string                              |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M5:   return "M5";
      case PERIOD_M15:  return "M15";
      case PERIOD_H1:   return "H1";
      default:          return "Unknown";
     }
  }
//+------------------------------------------------------------------+
