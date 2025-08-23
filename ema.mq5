//+------------------------------------------------------------------+
//|                        EMA_Meta_Alerts.mq5                       |
//|                Author: Essien Abasiama © 2025 Abasiama           |
//+------------------------------------------------------------------+
#property copyright "Essien Abasiama © 2025 Abasiama"
#property link      "https://www.mql5.com"
#property version   "1.25"
#property strict

//--- Inputs
input int   Fast_MA         = 10;     // Fast EMA length
input int   Slow_MA         = 10;     // Slow SMA length
input int   LookBackBars    = 500;    // How many bars back to scan for historical crosses (per TF)
input bool  Draw_X_Marks    = true;   // Draw X marks on chart
input color CrossColor      = clrRed; // Color for the X marks
input int   CrossFontSize   = 14;     // Font size for the X marks

//--- Timeframes to monitor
ENUM_TIMEFRAMES TFs[3] = { PERIOD_M5, PERIOD_M15, PERIOD_H1 };

//--- Memory to avoid duplicates
datetime lastSentCrossTime[3];

//--- Backend endpoint
string BASE_URL = "https://2c9dda212754.ngrok-free.app/meta";

//--- Global handles for visible indicators
int fastHandleMain = INVALID_HANDLE;
int slowHandleMain = INVALID_HANDLE;

//--- Indicator names for cleanup
string fastShortName = "Fast EMA";
string slowShortName = "Slow SMA";

//--- Forward declarations
string TimeframeToString(ENUM_TIMEFRAMES tf);
void   DrawHistoricalCrosses(int index, ENUM_TIMEFRAMES tf, int lookback);
void   CheckRealtimeCross(int index, ENUM_TIMEFRAMES tf);
void   CreateXMark(string tfName, datetime crossTime, double crossPrice);
void   DeleteOurHistoricalMarks();
string JsonEscape(string s);
void   SendToBackend(string symbol,string signal,string timeframe,double price,string message);

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("✅ EMA/SMA Cross EA Initialized for ", _Symbol);

   DeleteOurHistoricalMarks();

   // Attach visible EMA + SMA
   fastHandleMain = iMA(_Symbol, PERIOD_CURRENT, Fast_MA, 0, MODE_EMA, PRICE_CLOSE);
   slowHandleMain = iMA(_Symbol, PERIOD_CURRENT, Slow_MA, 0, MODE_SMA, PRICE_CLOSE);

   if(fastHandleMain != INVALID_HANDLE)
      ChartIndicatorAdd(0, 0, fastHandleMain);
   else
      Print("❌ Failed to create fast EMA handle.");

   if(slowHandleMain != INVALID_HANDLE)
      ChartIndicatorAdd(0, 0, slowHandleMain);
   else
      Print("❌ Failed to create slow SMA handle.");

   // Historical scan
   for(int i=0; i<ArraySize(TFs); i++)
      DrawHistoricalCrosses(i, TFs[i], LookBackBars);

   // Test connection
  // SendToBackend(_Symbol, "TEST", "INIT", SymbolInfoDouble(_Symbol, SYMBOL_BID),
  //               "Init message from MT5 EA");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(fastHandleMain != INVALID_HANDLE)
   {
      ChartIndicatorDelete(0, 0, fastShortName);
      IndicatorRelease(fastHandleMain);
      fastHandleMain = INVALID_HANDLE;
   }

   if(slowHandleMain != INVALID_HANDLE)
   {
      ChartIndicatorDelete(0, 0, slowShortName);
      IndicatorRelease(slowHandleMain);
      slowHandleMain = INVALID_HANDLE;
   }

   // If you want to auto-remove X marks:
   // DeleteOurHistoricalMarks();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   for(int i=0; i<ArraySize(TFs); i++)
      CheckRealtimeCross(i, TFs[i]);
}

//+------------------------------------------------------------------+
//| Historical crosses                                               |
//+------------------------------------------------------------------+
void DrawHistoricalCrosses(int index, ENUM_TIMEFRAMES tf, int lookback)
{
   string tfName = TimeframeToString(tf);
   int totalBars = Bars(_Symbol, tf);
   if(totalBars < 3) return;

   int neededBars = MathMin(MathMax(lookback + 2, 10), totalBars);

   int fastHandle = iMA(_Symbol, tf, Fast_MA, 0, MODE_EMA, PRICE_CLOSE);
   int slowHandle = iMA(_Symbol, tf, Slow_MA, 0, MODE_SMA, PRICE_CLOSE);

   double fastArr[], slowArr[];
   ArraySetAsSeries(fastArr, true);
   ArraySetAsSeries(slowArr, true);

   if(CopyBuffer(fastHandle, 0, 0, neededBars, fastArr) < 2 ||
      CopyBuffer(slowHandle, 0, 0, neededBars, slowArr) < 2)
   {
      IndicatorRelease(fastHandle);
      IndicatorRelease(slowHandle);
      return;
   }

   datetime mostRecentCross = 0;
   for(int j=1; j<neededBars; j++)
   {
      double d_now = fastArr[j-1] - slowArr[j-1];
      double d_prev= fastArr[j]   - slowArr[j];

      if(d_now * d_prev < 0.0) // cross
      {
         datetime crossTime = iTime(_Symbol, tf, j-1);
         double crossPrice  = (fastArr[j-1] + slowArr[j-1]) / 2.0; // ✅ Midpoint
         CreateXMark(tfName, crossTime, crossPrice);
         if(crossTime > mostRecentCross) mostRecentCross = crossTime;
      }
   }

   if(mostRecentCross > 0)
      lastSentCrossTime[index] = mostRecentCross;

   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);

   Print("✅ Historical crosses drawn for ", tfName);
}

//+------------------------------------------------------------------+
//| Realtime cross check                                             |
//+------------------------------------------------------------------+
void CheckRealtimeCross(int index, ENUM_TIMEFRAMES tf)
{
   string tfName = TimeframeToString(tf);

   int fastHandle = iMA(_Symbol, tf, Fast_MA, 0, MODE_EMA, PRICE_CLOSE);
   int slowHandle = iMA(_Symbol, tf, Slow_MA, 0, MODE_SMA, PRICE_CLOSE);

   double fastArr[2], slowArr[2];
   ArraySetAsSeries(fastArr, true);
   ArraySetAsSeries(slowArr, true);

   if(CopyBuffer(fastHandle, 0, 0, 2, fastArr) < 2 ||
      CopyBuffer(slowHandle, 0, 0, 2, slowArr) < 2)
   {
      IndicatorRelease(fastHandle);
      IndicatorRelease(slowHandle);
      return;
   }

   double d_now  = fastArr[0] - slowArr[0];
   double d_prev = fastArr[1] - slowArr[1];

   if(d_now * d_prev < 0.0) // cross
   {
      datetime crossTime = iTime(_Symbol, tf, 0);
      double crossPrice  = (fastArr[0] + slowArr[0]) / 2.0; // ✅ Midpoint

      if(lastSentCrossTime[index] != crossTime)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         string msg = "EMA/SMA Cross on " + _Symbol +
                      "\nTF: " + tfName +
                      "\nPrice: " + DoubleToString(bid, _Digits);

         SendToBackend(_Symbol, "CROSS", tfName, bid, msg);
         CreateXMark(tfName, crossTime, crossPrice);
         lastSentCrossTime[index] = crossTime;

         Print("✅ Realtime EMA/SMA cross on ", tfName);
      }
   }

   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
}

//+------------------------------------------------------------------+
//| Draw X Mark                                                      |
//+------------------------------------------------------------------+
void CreateXMark(string tfName, datetime crossTime, double crossPrice)
{
   string name = StringFormat("X_%s_%d", tfName, (int)crossTime);

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, crossTime, crossPrice);
      ObjectSetString(0, name, OBJPROP_TEXT, "X");
      ObjectSetInteger(0, name, OBJPROP_COLOR, CrossColor);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, CrossFontSize);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   }
}

//+------------------------------------------------------------------+
//| Delete old marks                                                 |
//+------------------------------------------------------------------+
void DeleteOurHistoricalMarks()
{
   int total = ObjectsTotal(0);
   for(int i=total-1; i>=0; --i)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, "X_") == 0)
         ObjectDelete(0, nm);
   }
}

//+------------------------------------------------------------------+
//| JSON Escape                                                      |
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
//| Send JSON to backend                                             |
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

   uchar post[];
   StringToCharArray(json, post, 0, StringLen(json), CP_UTF8);

   string reqHeaders="Content-Type: application/json\r\n";
   string resHeaders="";
   uchar result[];

   int res=WebRequest("POST", BASE_URL, reqHeaders, 5000, post, result, resHeaders);

   if(res==-1)
      Print("❌ WebRequest failed: ", GetLastError());
   else
      Print("✅ Backend reply: ", CharArrayToString(result,0,-1,CP_UTF8));
}

//+------------------------------------------------------------------+
//| Timeframe to string                                              |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      default:         return "TF";
   }
}
//+------------------------------------------------------------------+
