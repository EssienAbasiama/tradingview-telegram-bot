//+------------------------------------------------------------------+
//| SMART EMA TELEGRAM ENGINE                                        |
//| Multi-Symbol | Per-Pair Settings | Telegram Controlled           |
//| Author: Essien Abasiama © 2025                                   |
//+------------------------------------------------------------------+
#property strict
#property version "5.0"

//=========================== BACKEND ==============================//
string BASE_URL = "https://tradingview-telegram-bot-3f68.onrender.com/api/status";
string COMMANDS_URL = "https://tradingview-telegram-bot-3f68.onrender.com/api/commands";

//=========================== GLOBAL CONTROL =======================//
bool IsPaused = false;
bool TestSent = false; // <-- Added (does not remove anything)
string SYMBOLS_FILE = "symbols.txt";
int CROSS_HISTORY_BARS = 800;

bool EnsureSymbolReady(string sym)
{
   if (StringLen(sym) == 0)
      return false;

   if (!SymbolSelect(sym, true))
   {
      PrintFormat("Failed to select symbol: %s", sym);
      return false;
   }
   return true;
}

long EnsureSymbolChart(string sym, ENUM_TIMEFRAMES tf)
{
   long chartId = ChartFirst();
   while (chartId >= 0)
   {
      if (ChartSymbol(chartId) == sym)
      {
         ChartSetSymbolPeriod(chartId, sym, tf);
         return chartId;
      }
      chartId = ChartNext(chartId);
   }

   long openedChart = ChartOpen(sym, tf);
   if (openedChart <= 0)
   {
      PrintFormat("Failed to open chart for %s", sym);
      return -1;
   }

   ChartSetSymbolPeriod(openedChart, sym, tf);
   return openedChart;
}

//=========================== STRUCT ===============================//
struct SymbolState
{
   string symbol;
   bool enableCross;
   bool enableTrend;
   bool enableVolume;
   ENUM_TIMEFRAMES crossTF;
   ENUM_TIMEFRAMES trendTF1;
   ENUM_TIMEFRAMES trendTF2;
   int fastMA;
   int slowMA;
   datetime lastCrossTime;
   datetime lastVolumeTime;
   datetime lastTrendTime;
   string lastTrendState;
};

SymbolState Symbols[];
int SymbolCount = 0;

void DrawXMarkOnChart(long chartId, string symbol, datetime t, double price);
void DrawXMarkForSymbolCharts(string symbol, datetime t, double price);
void RedrawHistoricalCrossesForSymbolCharts(SymbolState &s);

void AttachCrossIndicatorsForSymbol(SymbolState &s)
{
   long chartId = EnsureSymbolChart(s.symbol, s.crossTF);
   if (chartId < 0)
      return;

   int fastHandle = iMA(s.symbol, s.crossTF, s.fastMA, 0, MODE_EMA, PRICE_CLOSE);
   int slowHandle = iMA(s.symbol, s.crossTF, s.slowMA, 0, MODE_SMA, PRICE_CLOSE);

   if (fastHandle != INVALID_HANDLE)
      ChartIndicatorAdd(chartId, 0, fastHandle);
   if (slowHandle != INVALID_HANDLE)
      ChartIndicatorAdd(chartId, 0, slowHandle);

   // Show historical crosses immediately after attaching indicators.
   RedrawHistoricalCrossesForSymbolCharts(s);
}

//=========================== INIT =================================//
int OnInit()
{
   Print("Smart Telegram Multi-Symbol Engine Initialized");

   LoadSymbols();
   if (SymbolCount == 0)
      AddSymbol(_Symbol);

   return (INIT_SUCCEEDED);
}

//=========================== TICK =================================//
void OnTick()
{
   CheckBackendCommands();

   // Send test alerts once after first tick
   if (!TestSent)
   {
      TestAlerts();
      TestSent = true;
   }

   if (IsPaused)
      return;

   for (int i = 0; i < SymbolCount; i++)
      ProcessSymbol(Symbols[i]);
}

//=========================== SYMBOL MANAGEMENT ====================//
void AddSymbol(string sym)
{
   if (!EnsureSymbolReady(sym))
      return;

   for (int i = 0; i < SymbolCount; i++)
      if (Symbols[i].symbol == sym)
         return;

   ArrayResize(Symbols, SymbolCount + 1);

   Symbols[SymbolCount].symbol = sym;
   Symbols[SymbolCount].enableCross = true;
   Symbols[SymbolCount].enableTrend = true;
   Symbols[SymbolCount].enableVolume = true;
   Symbols[SymbolCount].crossTF = PERIOD_H1;
   Symbols[SymbolCount].trendTF1 = PERIOD_H4;
   Symbols[SymbolCount].trendTF2 = PERIOD_D1;
   Symbols[SymbolCount].fastMA = 10;
   Symbols[SymbolCount].slowMA = 10;
   Symbols[SymbolCount].lastCrossTime = 0;
   Symbols[SymbolCount].lastVolumeTime = 0;
   Symbols[SymbolCount].lastTrendTime = 0;
   Symbols[SymbolCount].lastTrendState = "";

   SymbolCount++;
   SaveSymbols();

   // Draw historical crosses for newly added symbols.
   RedrawHistoricalCrossesForSymbolCharts(Symbols[SymbolCount - 1]);
   AttachCrossIndicatorsForSymbol(Symbols[SymbolCount - 1]);
}

void RemoveSymbol(string sym)
{
   for (int i = 0; i < SymbolCount; i++)
   {
      if (Symbols[i].symbol == sym)
      {
         for (int j = i; j < SymbolCount - 1; j++)
            Symbols[j] = Symbols[j + 1];

         SymbolCount--;
         ArrayResize(Symbols, SymbolCount);
         SaveSymbols();
         break;
      }
   }
}

//=========================== PERSISTENCE ==========================//
void SaveSymbols()
{
   int file = FileOpen(SYMBOLS_FILE, FILE_WRITE | FILE_TXT);
   if (file < 0)
   {
      Print("Failed to save symbols");
      return;
   }
   for (int i = 0; i < SymbolCount; i++)
      FileWrite(file, Symbols[i].symbol);
   FileClose(file);
}

void LoadSymbols()
{
   int file = FileOpen(SYMBOLS_FILE, FILE_READ | FILE_TXT);
   if (file < 0)
   {
      Print("No saved symbols");
      return;
   }

   while (!FileIsEnding(file))
   {
      string sym = FileReadString(file);
      if (StringLen(sym) > 0)
         AddSymbolInternal(sym);
   }
   FileClose(file);
}

void AddSymbolInternal(string sym)
{
   if (!EnsureSymbolReady(sym))
      return;

   for (int i = 0; i < SymbolCount; i++)
      if (Symbols[i].symbol == sym)
         return;

   ArrayResize(Symbols, SymbolCount + 1);

   Symbols[SymbolCount].symbol = sym;
   Symbols[SymbolCount].enableCross = true;
   Symbols[SymbolCount].enableTrend = true;
   Symbols[SymbolCount].enableVolume = true;
   Symbols[SymbolCount].crossTF = PERIOD_H1;
   Symbols[SymbolCount].trendTF1 = PERIOD_H4;
   Symbols[SymbolCount].trendTF2 = PERIOD_D1;
   Symbols[SymbolCount].fastMA = 10;
   Symbols[SymbolCount].slowMA = 10;
   Symbols[SymbolCount].lastCrossTime = 0;
   Symbols[SymbolCount].lastVolumeTime = 0;
   Symbols[SymbolCount].lastTrendTime = 0;
   Symbols[SymbolCount].lastTrendState = "";

   SymbolCount++;

   // Draw historical crosses for symbols loaded from file.
   RedrawHistoricalCrossesForSymbolCharts(Symbols[SymbolCount - 1]);
   AttachCrossIndicatorsForSymbol(Symbols[SymbolCount - 1]);
}

//=========================== CORE PROCESS =========================//
void ProcessSymbol(SymbolState &s)
{
   if (!EnsureSymbolReady(s.symbol))
      return;

   if (s.enableCross)
      CheckCross(s);
   if (s.enableVolume)
      CheckVolume(s);
   if (s.enableTrend)
      CheckTrend(s);
}

//=========================== CROSS ================================//
void CheckCross(SymbolState &s)
{
   int fastHandle = iMA(s.symbol, s.crossTF, s.fastMA, 0, MODE_EMA, PRICE_CLOSE);
   int slowHandle = iMA(s.symbol, s.crossTF, s.slowMA, 0, MODE_SMA, PRICE_CLOSE);

   double fast[2], slow[2];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if (CopyBuffer(fastHandle, 0, 0, 2, fast) < 2 || CopyBuffer(slowHandle, 0, 0, 2, slow) < 2)
   {
      IndicatorRelease(fastHandle);
      IndicatorRelease(slowHandle);
      return;
   }

   // Include zero-touch transitions so crosses are not missed when values become exactly equal.
   double d_now = fast[0] - slow[0];
   double d_prev = fast[1] - slow[1];
   bool crossed = ((d_now > 0.0 && d_prev <= 0.0) ||
                   (d_now < 0.0 && d_prev >= 0.0));

   if (crossed)
   {
      datetime t = iTime(s.symbol, s.crossTF, 0);
      if (t != s.lastCrossTime)
      {
         double price = SymbolInfoDouble(s.symbol, SYMBOL_BID);
         string msg = "EMA/SMA Cross on " + s.symbol + "\nTF: " + EnumToString(s.crossTF) + "\nPrice: " + DoubleToString(price, _Digits);
         SendToBackend(s.symbol, "CROSS", EnumToString(s.crossTF), price, msg);

         // Draw on every open chart that matches this symbol.
         DrawXMarkForSymbolCharts(s.symbol, t, (fast[0] + slow[0]) / 2.0);
         s.lastCrossTime = t;
      }
   }

   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
}

//=========================== VOLUME ===============================//
void CheckVolume(SymbolState &s)
{
   if (s.crossTF != PERIOD_H1)
      return;

   long vol = iVolume(s.symbol, PERIOD_H1, 0);
   double avg = 0;
   for (int i = 1; i <= 20; i++)
      avg += iVolume(s.symbol, PERIOD_H1, i);
   avg /= 20;

   if (avg > 0 && vol > 2.5 * avg)
   {
      datetime t = iTime(s.symbol, PERIOD_H1, 0);
      if (t != s.lastVolumeTime)
      {
         double price = SymbolInfoDouble(s.symbol, SYMBOL_BID);
         string msg = "Volume Spike on " + s.symbol + "\nTF: H1";
         SendToBackend(s.symbol, "VOLUME_SPIKE", "H1", price, msg);
         s.lastVolumeTime = t;
      }
   }
}

//=========================== TREND ================================//
void CheckTrend(SymbolState &s)
{
   string t1 = TrendDir(s.symbol, s.trendTF1, s.fastMA, s.slowMA);
   string t2 = TrendDir(s.symbol, s.trendTF2, s.fastMA, s.slowMA);

   if (t1 == "" || t2 == "")
      return;
   if (t1 != t2)
      return;

   string newSignal = "TREND_" + t1;
   datetime nowBar = iTime(s.symbol, s.trendTF1, 0);

   if (newSignal != s.lastTrendState || nowBar != s.lastTrendTime)
   {
      double price = SymbolInfoDouble(s.symbol, SYMBOL_BID);
      string msg = "Trend update " + s.symbol + "\n" + EnumToString(s.trendTF1) + ": " + t1 + "\n" + EnumToString(s.trendTF2) + ": " + t2;
      SendToBackend(s.symbol, newSignal, "TREND", price, msg);
      s.lastTrendState = newSignal;
      s.lastTrendTime = nowBar;
   }
}

string TrendDir(string sym, ENUM_TIMEFRAMES tf, int fastMA, int slowMA)
{
   if (!EnsureSymbolReady(sym))
      return "";

   int fast = iMA(sym, tf, fastMA, 0, MODE_EMA, PRICE_CLOSE);
   int slow = iMA(sym, tf, slowMA, 0, MODE_SMA, PRICE_CLOSE);

   if (fast == INVALID_HANDLE || slow == INVALID_HANDLE)
   {
      if (fast != INVALID_HANDLE)
         IndicatorRelease(fast);
      if (slow != INVALID_HANDLE)
         IndicatorRelease(slow);
      return "";
   }

   double f[1], sma[1];
   ArraySetAsSeries(f, true);
   ArraySetAsSeries(sma, true);

   if (CopyBuffer(fast, 0, 0, 1, f) < 1 || CopyBuffer(slow, 0, 0, 1, sma) < 1)
   {
      IndicatorRelease(fast);
      IndicatorRelease(slow);
      return "";
   }

   string result = "";
   if (f[0] > sma[0])
      result = "BULLISH";
   else if (f[0] < sma[0])
      result = "BEARISH";

   IndicatorRelease(fast);
   IndicatorRelease(slow);
   return result;
}

//=========================== DRAW ================================//
void DrawXMark(datetime t, double price)
{
   string name = "X_" + (string)t;
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
      ObjectSetString(0, name, OBJPROP_TEXT, "X");
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 14);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   }
}

//=========================== BACKEND =============================//
void SendToBackend(string symbol, string signal, string tf, double price, string msg)
{
   // escape JSON string values to ensure valid JSON when msg contains newlines or quotes
   string escDetails = JsonEscape(msg);
   string json = "{\"type\":\"" + signal + "\",\"symbol\":\"" + symbol + "\",\"result\":\"" + signal + "\",\"details\":\"" + escDetails + "\",\"price\":\"" + DoubleToString(price, _Digits) + "\"}";
   uchar post[];
   StringToCharArray(json, post, 0, StringLen(json));
   string headers = "Content-Type: application/json\r\n";
   string cookie = "";
   uchar result[];
   string resHeaders;

   PrintFormat("WebRequest POST -> %s (payload len=%d)", BASE_URL, StringLen(json));
   int respCode = WebRequest("POST", BASE_URL, headers, cookie, 10000, post, StringLen(json), result, resHeaders);
   PrintFormat("WebRequest POST -> %s resp=%d", BASE_URL, respCode);
   if (ArraySize(result) > 0)
      Print("POST response: " + CharArrayToString(result));
   else
      Print("POST response: <empty>");
   if (respCode <= 0)
      PrintFormat("WebRequest error: respCode=%d, headers=%s", respCode, resHeaders);
}

//=========================== COMMAND POLLING ======================//
void CheckBackendCommands()
{
   static datetime lastCheck = 0;
   if (TimeCurrent() - lastCheck < 5)
      return;
   lastCheck = TimeCurrent();

   uchar post[];
   uchar result[];
   string headers = "";
   string cookie = "";
   string resHeaders;

   int respCode = WebRequest("GET", COMMANDS_URL, headers, cookie, 5000, post, 0, result, resHeaders);
   if (respCode != 200)
   {
      PrintFormat("Command poll failed: %d", respCode);
      return;
   }

   string response = CharArrayToString(result);
   ParseAndExecuteCommands(response);
}

//=========================== JSON & COMMANDS =====================//
int StringFindPos(const string text, const string substr, int startPos = 0)
{
   for (int i = startPos; i <= StringLen(text) - StringLen(substr); i++)
      if (StringSubstr(text, i, StringLen(substr)) == substr)
         return i;
   return -1;
}

int FindMatchingBrace(const string text, int openPos)
{
   if (openPos < 0 || openPos >= StringLen(text) || StringGetCharacter(text, openPos) != '{')
      return -1;

   int depth = 0;
   bool inString = false;
   bool escaped = false;

   for (int i = openPos; i < StringLen(text); i++)
   {
      int c = StringGetCharacter(text, i);

      if (inString)
      {
         if (escaped)
         {
            escaped = false;
            continue;
         }
         if (c == '\\')
         {
            escaped = true;
            continue;
         }
         if (c == '"')
            inString = false;
         continue;
      }

      if (c == '"')
      {
         inString = true;
         continue;
      }

      if (c == '{')
      {
         depth++;
         continue;
      }

      if (c == '}')
      {
         depth--;
         if (depth == 0)
            return i;
      }
   }

   return -1;
}

string JsonGetValue(const string json, const string key, int startPos = 0)
{
   string pattern = "\"" + key + "\":\"";
   int p = StringFindPos(json, pattern, startPos);
   if (p < 0)
      return "";
   p += StringLen(pattern);
   int q = StringFindPos(json, "\"", p);
   if (q < 0)
      return "";
   return StringSubstr(json, p, q - p);
}

string JsonGetObject(const string json, const string key)
{
   string pattern = "\"" + key + "\":{";
   int p = StringFindPos(json, pattern, 0);
   if (p < 0)
      return "";

   int objStart = p + StringLen(pattern) - 1;
   int objEnd = FindMatchingBrace(json, objStart);
   if (objEnd < 0)
      return "";

   return StringSubstr(json, objStart, objEnd - objStart + 1);
}

int JsonGetIntValue(const string json, const string key, int defaultValue = 0)
{
   string pattern = "\"" + key + "\":";
   int p = StringFindPos(json, pattern, 0);
   if (p < 0)
      return defaultValue;

   p += StringLen(pattern);
   while (p < StringLen(json))
   {
      int c = StringGetCharacter(json, p);
      if (c != ' ' && c != '\t' && c != '\r' && c != '\n')
         break;
      p++;
   }

   bool quoted = false;
   if (p < StringLen(json) && StringGetCharacter(json, p) == '"')
   {
      quoted = true;
      p++;
   }

   int q = p;
   while (q < StringLen(json))
   {
      int c = StringGetCharacter(json, q);
      if (quoted)
      {
         if (c == '"')
            break;
      }
      else
      {
         if (c == ',' || c == '}' || c == ']')
            break;
      }
      q++;
   }

   if (q <= p)
      return defaultValue;

   string raw = StringSubstr(json, p, q - p);
   StringTrimLeft(raw);
   StringTrimRight(raw);
   if (StringLen(raw) == 0)
      return defaultValue;

   return (int)StringToInteger(raw);
}

bool TimeframeFromText(string tfText, ENUM_TIMEFRAMES &tf)
{
   StringTrimLeft(tfText);
   StringTrimRight(tfText);
   StringToUpper(tfText);

   if (tfText == "M1")
      tf = PERIOD_M1;
   else if (tfText == "M5")
      tf = PERIOD_M5;
   else if (tfText == "M15")
      tf = PERIOD_M15;
   else if (tfText == "M30")
      tf = PERIOD_M30;
   else if (tfText == "H1")
      tf = PERIOD_H1;
   else if (tfText == "H4")
      tf = PERIOD_H4;
   else if (tfText == "D1")
      tf = PERIOD_D1;
   else if (tfText == "PERIOD_M1")
      tf = PERIOD_M1;
   else if (tfText == "PERIOD_M5")
      tf = PERIOD_M5;
   else if (tfText == "PERIOD_M15")
      tf = PERIOD_M15;
   else if (tfText == "PERIOD_M30")
      tf = PERIOD_M30;
   else if (tfText == "PERIOD_H1")
      tf = PERIOD_H1;
   else if (tfText == "PERIOD_H4")
      tf = PERIOD_H4;
   else if (tfText == "PERIOD_D1")
      tf = PERIOD_D1;
   else if (tfText == "1" || tfText == "1M" || tfText == "1MIN" || tfText == "MIN1")
      tf = PERIOD_M1;
   else if (tfText == "5" || tfText == "5M" || tfText == "5MIN" || tfText == "MIN5")
      tf = PERIOD_M5;
   else if (tfText == "15" || tfText == "15M" || tfText == "15MIN" || tfText == "MIN15")
      tf = PERIOD_M15;
   else if (tfText == "30" || tfText == "30M" || tfText == "30MIN" || tfText == "MIN30")
      tf = PERIOD_M30;
   else if (tfText == "60" || tfText == "1H" || tfText == "H60" || tfText == "HOUR1")
      tf = PERIOD_H1;
   else if (tfText == "240" || tfText == "4H" || tfText == "H4" || tfText == "HOUR4")
      tf = PERIOD_H4;
   else if (tfText == "1440" || tfText == "1D" || tfText == "D24" || tfText == "DAY1")
      tf = PERIOD_D1;
   else
      return false;

   return true;
}

void SendStatusForCommand(string commandId, string type, string symbol, string resultText, string details)
{
   string escDetails = JsonEscape(details);
   string json = "{\"commandId\":\"" + commandId + "\",\"type\":\"" + type + "\",\"symbol\":\"" + symbol + "\",\"result\":\"" + resultText + "\",\"details\":\"" + escDetails + "\"}";
   uchar post[];
   StringToCharArray(json, post, 0, StringLen(json));
   string headers = "Content-Type: application/json\r\n";
   string cookie = "";
   uchar resp[];
   string resHeaders;

   PrintFormat("SendStatusForCommand POST -> %s (payload len=%d)", BASE_URL, StringLen(json));
   int respCode = WebRequest("POST", BASE_URL, headers, cookie, 10000, post, StringLen(json), resp, resHeaders);
   PrintFormat("SendStatusForCommand POST -> %s resp=%d", BASE_URL, respCode);
   if (ArraySize(resp) > 0)
      Print("SendStatusForCommand response: " + CharArrayToString(resp));
   else
      Print("SendStatusForCommand response: <empty>");
   if (respCode <= 0)
      PrintFormat("SendStatusForCommand error: respCode=%d, headers=%s", respCode, resHeaders);
}

void ParseAndExecuteCommands(string json)
{
   int pos = StringFind(json, "\"commands\"");
   if (pos < 0)
      return;

   int arrStart = StringFind(json, "[", pos);
   if (arrStart < 0)
      return;

   int i = arrStart + 1;
   while (true)
   {
      int objStart = StringFindPos(json, "{", i);
      if (objStart < 0)
         break;
      int objEnd = FindMatchingBrace(json, objStart);
      if (objEnd < 0)
         break;

      string obj = StringSubstr(json, objStart, objEnd - objStart + 1);
      string id = JsonGetValue(obj, "id");
      string type = JsonGetValue(obj, "type");
      string symbol = JsonGetValue(obj, "symbol");

      if (type == "")
      {
         i = objEnd + 1;
         continue;
      }

      if (type == "get_symbols")
         SendAvailableSymbols(id);
      else if (type == "add_pair")
      {
         if (StringLen(symbol) > 0)
            AddSymbol(symbol);
         SendStatusForCommand(id, type, symbol, "ok", "added symbol");
         SendActiveSymbols(id);
      }
      else if (type == "remove_pair")
      {
         if (StringLen(symbol) > 0)
            RemoveSymbol(symbol);
         SendStatusForCommand(id, type, symbol, "ok", "removed symbol");
         SendActiveSymbols(id);
      }
      else if (type == "pause_ea")
      {
         IsPaused = true;
         SendStatusForCommand(id, type, "", "ok", "EA paused");
      }
      else if (type == "resume_ea")
      {
         IsPaused = false;
         SendStatusForCommand(id, type, "", "ok", "EA resumed");
      }
      else if (type == "get_active_symbols")
      {
         SendActiveSymbols(id);
      }
      else if (type == "test_alert")
      {
         // Execute a test alert on demand and report completion
         TestAlerts();
         SendStatusForCommand(id, type, symbol, "ok", "test alert dispatched");
      }
      else if (type == "update_strategy")
      {
         bool found = false;

         if (StringLen(symbol) > 0)
            AddSymbol(symbol);

         for (int idx = 0; idx < SymbolCount; idx++)
         {
            if (Symbols[idx].symbol != symbol)
               continue;

            found = true;

            // Telegram commands are typically nested as payload.settings.{...}
            // Keep backward compatibility with flat keys.
            string payloadObj = JsonGetObject(obj, "payload");
            string settingsObj = "";
            if (StringLen(payloadObj) > 0)
               settingsObj = JsonGetObject(payloadObj, "settings");
            if (StringLen(settingsObj) == 0)
               settingsObj = JsonGetObject(obj, "settings");

            string crossTFText = JsonGetValue(settingsObj, "crossTF");
            if (StringLen(crossTFText) == 0)
               crossTFText = JsonGetValue(obj, "crossTF");

            string trendTF1Text = JsonGetValue(settingsObj, "trendTF1");
            if (StringLen(trendTF1Text) == 0)
               trendTF1Text = JsonGetValue(obj, "trendTF1");

            string trendTF2Text = JsonGetValue(settingsObj, "trendTF2");
            if (StringLen(trendTF2Text) == 0)
               trendTF2Text = JsonGetValue(obj, "trendTF2");

            string trendTFText = JsonGetValue(settingsObj, "trendTF");
            if (StringLen(trendTFText) == 0)
               trendTFText = JsonGetValue(obj, "trendTF");
            if (StringLen(trendTFText) == 0)
               trendTFText = JsonGetValue(settingsObj, "trendTimeframe");
            if (StringLen(trendTFText) == 0)
               trendTFText = JsonGetValue(obj, "trendTimeframe");
            if (StringLen(trendTFText) == 0)
               trendTFText = JsonGetValue(settingsObj, "trendlineTF");
            if (StringLen(trendTFText) == 0)
               trendTFText = JsonGetValue(obj, "trendlineTF");

            if (StringLen(trendTF1Text) == 0)
               trendTF1Text = trendTFText;
            if (StringLen(trendTF2Text) == 0)
               trendTF2Text = trendTFText;

            int fast = JsonGetIntValue(settingsObj, "fastMA", 0);
            if (fast <= 0)
               fast = JsonGetIntValue(obj, "fastMA", 0);

            int slow = JsonGetIntValue(settingsObj, "slowMA", 0);
            if (slow <= 0)
               slow = JsonGetIntValue(obj, "slowMA", 0);

            ENUM_TIMEFRAMES tf;
            if (StringLen(crossTFText) > 0 && TimeframeFromText(crossTFText, tf))
               Symbols[idx].crossTF = tf;
            if (StringLen(trendTF1Text) > 0 && TimeframeFromText(trendTF1Text, tf))
               Symbols[idx].trendTF1 = tf;
            if (StringLen(trendTF2Text) > 0 && TimeframeFromText(trendTF2Text, tf))
               Symbols[idx].trendTF2 = tf;
            if (fast > 0)
               Symbols[idx].fastMA = fast;
            if (slow > 0)
               Symbols[idx].slowMA = slow;

            PrintFormat("update_strategy applied: %s | crossTF=%s trendTF1=%s trendTF2=%s fastMA=%d slowMA=%d",
                        Symbols[idx].symbol,
                        EnumToString(Symbols[idx].crossTF),
                        EnumToString(Symbols[idx].trendTF1),
                        EnumToString(Symbols[idx].trendTF2),
                        Symbols[idx].fastMA,
                        Symbols[idx].slowMA);

            // Rebuild historical cross marks when TF/MA settings change.
            RedrawHistoricalCrossesForSymbolCharts(Symbols[idx]);

            break;
         }

         if (found)
            SendStatusForCommand(id, type, symbol, "ok", "strategy updated");
         else
            SendStatusForCommand(id, type, symbol, "error", "symbol not found");
      }
      else if (StringFindPos(type, "toggle_") >= 0)
      {
         string field = StringSubstr(type, StringFindPos(type, "toggle_") + 7);
         for (int idx = 0; idx < SymbolCount; idx++)
         {
            if (Symbols[idx].symbol == symbol)
            {
               if (field == "cross")
                  Symbols[idx].enableCross = !Symbols[idx].enableCross;
               else if (field == "trend")
                  Symbols[idx].enableTrend = !Symbols[idx].enableTrend;
               else if (field == "volume")
                  Symbols[idx].enableVolume = !Symbols[idx].enableVolume;
            }
         }
         SendStatusForCommand(id, type, symbol, "ok", "toggled " + field);
      }

      i = objEnd + 1;
   }
}

void SendAvailableSymbols(string commandId)
{
   string list = "";
   int total = SymbolsTotal(true);

   for (int i = 0; i < total; i++)
   {
      string sym = SymbolName(i, true);

      bool alreadyAdded = false;
      for (int j = 0; j < SymbolCount; j++)
      {
         if (Symbols[j].symbol == sym)
         {
            alreadyAdded = true;
            break;
         }
      }
      if (alreadyAdded)
         continue;

      if (StringLen(list) > 0)
         list += ",";
      list += sym;
   }

   SendStatusForCommand(commandId, "symbols_list", "ok", list, list);
}

string ReadSymbolsListFromFile()
{
   string list = "";
   int file = FileOpen(SYMBOLS_FILE, FILE_READ | FILE_TXT);
   if (file < 0)
      return "";

   while (!FileIsEnding(file))
   {
      string sym = FileReadString(file);
      if (StringLen(sym) > 0)
      {
         if (StringLen(list) > 0)
            list += ",";
         list += sym;
      }
   }
   FileClose(file);
   return list;
}

void SendActiveSymbols(string commandId)
{
   string list = ReadSymbolsListFromFile();
   if (StringLen(list) == 0)
   {
      SendStatusForCommand(commandId, "active_symbols", "empty", "", "No active symbols");
      return;
   }

   SendStatusForCommand(commandId, "active_symbols", "ok", list, list);
}

//--------------------- TEST ALERTS ---------------------//
void TestAlerts()
{
   string sym = _Symbol;
   double price = SymbolInfoDouble(sym, SYMBOL_BID);

   string crossMsg = "EMA/SMA Cross on " + sym + "\nTF: PERIOD_H1\nPrice: " + DoubleToString(price, _Digits);
   SendToBackend(sym, "CROSS", "PERIOD_H1", price, crossMsg);
   Print("Test CROSS alert sent");

   string trendMsg = "Trend update " + sym + "\nPERIOD_H4: BULLISH\nPERIOD_D1: BULLISH";
   SendToBackend(sym, "TREND_BULLISH", "PERIOD_H4", price, trendMsg);
   Print("Test TREND alert sent");
}

// Simple JSON string escaper
string JsonEscape(string s)
{
   if (StringLen(s) == 0)
      return s;
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, '"', "\\\"");
   StringReplace(s, "\n", "\\n");
   StringReplace(s, "\r", "\\r");
   StringReplace(s, "\t", "\\t");
   return s;
}

void DrawXMarkOnChart(long chartId, string symbol, datetime t, double price)
{
   string name = "X_" + symbol + "_" + (string)t;
   if (ObjectFind(chartId, name) < 0)
   {
      ObjectCreate(chartId, name, OBJ_TEXT, 0, t, price);
      ObjectSetString(chartId, name, OBJPROP_TEXT, "X");
      ObjectSetInteger(chartId, name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(chartId, name, OBJPROP_FONTSIZE, 14);
      ObjectSetInteger(chartId, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   }
}

void DrawXMarkForSymbolCharts(string symbol, datetime t, double price)
{
   bool drawn = false;
   long chartId = ChartFirst();
   while (chartId >= 0)
   {
      if (ChartSymbol(chartId) == symbol)
      {
         DrawXMarkOnChart(chartId, symbol, t, price);
         drawn = true;
      }
      chartId = ChartNext(chartId);
   }

   // Fallback to current chart if no chart is open for the symbol.
   if (!drawn)
   {
      long chartId = EnsureSymbolChart(symbol, PERIOD_CURRENT);
      if (chartId >= 0)
         DrawXMarkOnChart(chartId, symbol, t, price);
   }
}

void ClearXMarksOnChart(long chartId, string symbol)
{
   string prefix = "X_" + symbol + "_";
   int total = ObjectsTotal(chartId, 0, -1);
   for (int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(chartId, i, 0, -1);
      if (StringFind(name, prefix) == 0)
         ObjectDelete(chartId, name);
   }
}

void DrawHistoricalCrossesOnChart(long chartId, SymbolState &s)
{
   int bars = CROSS_HISTORY_BARS;
   if (bars < 50)
      bars = 50;

   int fastHandle = iMA(s.symbol, s.crossTF, s.fastMA, 0, MODE_EMA, PRICE_CLOSE);
   int slowHandle = iMA(s.symbol, s.crossTF, s.slowMA, 0, MODE_SMA, PRICE_CLOSE);

   if (fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
   {
      if (fastHandle != INVALID_HANDLE)
         IndicatorRelease(fastHandle);
      if (slowHandle != INVALID_HANDLE)
         IndicatorRelease(slowHandle);
      return;
   }

   double fast[];
   double slow[];
   datetime times[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(times, true);

   int need = bars + 2;
   int copiedFast = CopyBuffer(fastHandle, 0, 0, need, fast);
   int copiedSlow = CopyBuffer(slowHandle, 0, 0, need, slow);
   int copiedTime = CopyTime(s.symbol, s.crossTF, 0, need, times);
   int count = MathMin(copiedFast, MathMin(copiedSlow, copiedTime));

   if (count > 2)
   {
      // Skip index 0 (forming candle) and draw confirmed historical crosses.
      for (int i = count - 2; i >= 1; i--)
      {
         double dNow = fast[i] - slow[i];
         double dPrev = fast[i + 1] - slow[i + 1];
         bool crossed = ((dNow > 0.0 && dPrev <= 0.0) ||
                         (dNow < 0.0 && dPrev >= 0.0));
         if (crossed)
            DrawXMarkOnChart(chartId, s.symbol, times[i], (fast[i] + slow[i]) / 2.0);
      }
   }

   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
}

void RedrawHistoricalCrossesForSymbolCharts(SymbolState &s)
{
   bool matchedChart = false;
   long chartId = ChartFirst();
   while (chartId >= 0)
   {
      if (ChartSymbol(chartId) == s.symbol)
      {
         matchedChart = true;
         ClearXMarksOnChart(chartId, s.symbol);
         DrawHistoricalCrossesOnChart(chartId, s);
      }
      chartId = ChartNext(chartId);
   }

   // Fallback to current chart if it is the symbol chart.
   if (!matchedChart && s.symbol == _Symbol)
   {
      ClearXMarksOnChart(0, s.symbol);
      DrawHistoricalCrossesOnChart(0, s);
   }
}