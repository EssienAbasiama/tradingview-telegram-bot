//+------------------------------------------------------------------+
//|                        EMA_Meta_Alerts.mq5                      |
//|                Author: Essien Abasiama © 2025 Abasiama           |
//+------------------------------------------------------------------+
#property copyright "Essien Abasiama © 2025 Abasiama"
#property link      "https://www.mql5.com"
#property version   "1.11"
#property strict

input int Fast_MA = 9;    // Fast EMA
input int Slow_MA = 21;   // Slow EMA

// Timeframes to monitor
ENUM_TIMEFRAMES TFs[3] = { PERIOD_M5, PERIOD_M15, PERIOD_H1 };

// Memory to avoid duplicates
bool sentLong[3];
bool sentShort[3];

// Backend endpoint
string BASE_URL = "https://c280e4e87b61.ngrok-free.app/meta";

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("✅ EMA Meta Alert EA Initialized for ", _Symbol);
   ArrayInitialize(sentLong, false);
   ArrayInitialize(sentShort, false);

   // Test connection
   SendToBackend(_Symbol, "TEST", "INIT", SymbolInfoDouble(_Symbol, SYMBOL_BID),
                 "Dummy init message from MT5 EA");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   for(int i=0; i<ArraySize(TFs); i++)
   {
      CheckCross(i, TFs[i]);
   }
}

//+------------------------------------------------------------------+
//| Check EMA crossover for given timeframe                          |
//+------------------------------------------------------------------+
void CheckCross(int index, ENUM_TIMEFRAMES tf)
{
   string tfName = TimeframeToString(tf);

   // Create handles for EMA indicators
   int fastHandle = iMA(_Symbol, tf, Fast_MA, 0, MODE_EMA, PRICE_CLOSE);
   int slowHandle = iMA(_Symbol, tf, Slow_MA, 0, MODE_EMA, PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
   {
      Print("❌ Failed to create EMA handles on ", tfName);
      return;
   }

   double fast[3], slow[3];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(fastHandle, 0, 0, 3, fast) < 3) return;
   if(CopyBuffer(slowHandle, 0, 0, 3, slow) < 3) return;

   // Current vs previous values
   double fastNow = fast[0];
   double fastPrev = fast[1];
   double slowNow = slow[0];
   double slowPrev = slow[1];

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // --- LONG cross ---
   if(fastNow > slowNow && fastPrev <= slowPrev && !sentLong[index])
   {
      string msg = "📈 LONG EMA Cross on " + _Symbol +
                   "\n⏱ Timeframe: " + tfName +
                   "\nPrice: " + DoubleToString(bid,_Digits);

      SendToBackend(_Symbol, "LONG", tfName, bid, msg);
      DrawSignalArrow("LONG", tfName, bid);

      sentLong[index] = true;
      sentShort[index] = false;

      Print("✅ LONG cross detected on ", tfName);
   }

   // --- SHORT cross ---
   if(fastNow < slowNow && fastPrev >= slowPrev && !sentShort[index])
   {
      string msg = "📉 SHORT EMA Cross on " + _Symbol +
                   "\n⏱ Timeframe: " + tfName +
                   "\nPrice: " + DoubleToString(bid,_Digits);

      SendToBackend(_Symbol, "SHORT", tfName, bid, msg);
      DrawSignalArrow("SHORT", tfName, bid);

      sentShort[index] = true;
      sentLong[index] = false;

      Print("✅ SHORT cross detected on ", tfName);
   }

   // Release handles to avoid memory leak
   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
}

//+------------------------------------------------------------------+
//| Draw chart arrow                                                 |
//+------------------------------------------------------------------+
void DrawSignalArrow(string direction, string tfName, double price)
{
   string arrowName = direction + "_" + tfName + "_" + (string)TimeCurrent();

   if(direction == "LONG")
   {
      ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), price);
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, 233); // Up arrow
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
   }
   else if(direction == "SHORT")
   {
      ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), price);
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, 234); // Down arrow
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
   }
}

//+------------------------------------------------------------------+
//| Safe JSON escape                                                 |
//+------------------------------------------------------------------+
string JsonEscape(string s)
{
   string result="";
   for(int i=0; i<StringLen(s); i++)
   {
      ushort c=StringGetCharacter(s,i);
      switch(c)
      {
         case '\"': result+="\\\""; break;
         case '\\': result+="\\\\"; break;
         case '\n': result+="\\n"; break;
         case '\r': result+="\\r"; break;
         case '\t': result+="\\t"; break;
         default:   result+=ShortToString(c);
      }
   }
   return result;
}

//+------------------------------------------------------------------+
//| Send alert to backend                                            |
//+------------------------------------------------------------------+
void SendToBackend(string symbol,string signal,string timeframe,double price,string message)
{
   string ts = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);

   string json="{"
               +"\"symbol\":\""+JsonEscape(symbol)+"\","
               +"\"signal\":\""+JsonEscape(signal)+"\","
               +"\"timeframe\":\""+JsonEscape(timeframe)+"\","
               +"\"timestamp\":\""+JsonEscape(ts)+"\","
               +"\"price\":\""+DoubleToString(price,_Digits)+"\","
               +"\"message\":\""+JsonEscape(message)+"\""
               +"}";

   // ✅ copy WITHOUT terminating '\0'
   uchar post[];
   StringToCharArray(json, post, 0, StringLen(json), CP_UTF8);

   string reqHeaders="Content-Type: application/json\r\n";
   string resHeaders="";
   uchar result[];

   int res=WebRequest("POST", BASE_URL, reqHeaders, 5000, post, result, resHeaders);

   if(res==-1)
   {
      Print("❌ WebRequest failed: ", GetLastError());
   }
   else
   {
      string response=CharArrayToString(result,0,-1,CP_UTF8);
      Print("Response Code: ",res," | Backend Reply: ",response);
   }
}


//+------------------------------------------------------------------+
//| Convert timeframe to string                                      |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_H1:  return "H1";
      default:         return "Unknown";
   }
}
//+------------------------------------------------------------------+
