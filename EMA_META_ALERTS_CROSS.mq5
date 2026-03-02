//+------------------------------------------------------------------+
//| SMART EMA TELEGRAM ENGINE                                        |
//| Multi-Symbol | Per-Pair Settings | Telegram Controlled           |
//| Author: Essien Abasiama © 2025                                   |
//+------------------------------------------------------------------+
#property strict
#property version "5.0"

//=========================== BACKEND ==============================//
string BASE_URL = "https://35d2-102-88-111-120.ngrok-free.app/api/status";
string COMMANDS_URL = "https://35d2-102-88-111-120.ngrok-free.app/api/commands";

//=========================== GLOBAL CONTROL =======================//
bool IsPaused = false;
bool TestSent = false; // <-- Added (does not remove anything)
string SYMBOLS_FILE = "symbols.txt";

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

void ResetAllSymbols()
{
   // Clear memory
   SymbolCount = 0;
   ArrayResize(Symbols, 0);

   // Clear file by opening in WRITE mode and closing immediately
   int file = FileOpen(SYMBOLS_FILE, FILE_WRITE | FILE_TXT);
   if (file >= 0)
   {
      FileClose(file);
      Print("All symbols reset. symbols.txt cleared.");
   }
   else
   {
      Print("Failed to reset symbols file");
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
}

//=========================== CORE PROCESS =========================//
void ProcessSymbol(SymbolState &s)
{
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

   double d_now = fast[0] - slow[0];
   double d_prev = fast[1] - slow[1];

   if (d_now * d_prev < 0.0)
   {
      datetime t = iTime(s.symbol, s.crossTF, 0);
      if (t != s.lastCrossTime)
      {
         double price = SymbolInfoDouble(s.symbol, SYMBOL_BID);
         string msg = "EMA/SMA Cross on " + s.symbol + "\nTF: " + EnumToString(s.crossTF) + "\nPrice: " + DoubleToString(price, _Digits);
         SendToBackend(s.symbol, "CROSS", EnumToString(s.crossTF), price, msg);

         if (s.symbol == _Symbol)
            DrawXMark(t, (fast[0] + slow[0]) / 2.0);
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
   int fast = iMA(sym, tf, fastMA, 0, MODE_EMA, PRICE_CLOSE);
   int slow = iMA(sym, tf, slowMA, 0, MODE_SMA, PRICE_CLOSE);

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
      int objEnd = StringFindPos(json, "}", objStart);
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
      else if (type == "reset_pairs")
      {
         // Clear EA in-memory symbols and truncate symbols file
         ResetAllSymbols();
         SendStatusForCommand(id, type, "", "ok", "reset pairs");
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