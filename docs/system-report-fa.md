# 📋 **گزارش نهایی سیستم آربیتراژ v6.3**

---

## 📝 **معرفی سیستم**

سیستم آربیتراژ یک راه‌حل کامل برای تشخیص و اجرای معاملات آربیتراژ بین دو بروکر مختلف (LiteFinance و OpoFinance) با استفاده از **ZeroMQ** برای ارتباطات و **MetaTrader 4** برای اجرای معاملات است. این سیستم با معماری **Master-Slave** طراحی شده و از پروتکل‌های پیشرفته برای اطمینان از اجرای همزمان و ایمن معاملات استفاده می‌کند.

---

## 🏗️ **معماری سیستم**

```
┌─────────────────────────────────────────────────────────────────────┐
│                        ARBITRAGE SYSTEM v6.3                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────────┐         ┌──────────────────────┐        │
│  │   MASTER (LiteFinance)│         │   SLAVE (OpoFinance) │        │
│  │   XAUUSD_o           │         │   XAUUSD             │        │
│  │                      │         │                      │        │
│  │  ┌────────────────┐  │  ZMQ    │  ┌────────────────┐  │        │
│  │  │ PULL (5555)    │◄─┼─────────┼──│ PUSH           │  │        │
│  │  │ (Receive Price)│  │         │  │ (Send Price)    │  │        │
│  │  └────────────────┘  │         │  └────────────────┘  │        │
│  │                      │         │                      │        │
│  │  ┌────────────────┐  │  ZMQ    │  ┌────────────────┐  │        │
│  │  │ REQ (5556)     │──┼─────────┼─►│ REP            │  │        │
│  │  │ (Send Order)   │  │         │  │ (Receive Order) │  │        │
│  │  └────────────────┘  │         │  └────────────────┘  │        │
│  │                      │         │                      │        │
│  │  ┌────────────────┐  │         │  ┌────────────────┐  │        │
│  │  │ Risk Management│  │         │  │ Price Protect  │  │        │
│  │  │ - Take Profit  │  │         │  │ - Validate     │  │        │
│  │  │ - Stop Loss    │  │         │  │ - Slippage     │  │        │
│  │  │ - Trailing     │  │         │  │ - Lot Step     │  │        │
│  │  │ - Risk-Free    │  │         │  └────────────────┘  │        │
│  │  └────────────────┘  │         │                      │        │
│  └──────────────────────┘         └──────────────────────┘        │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    UI DISPLAY                              │   │
│  │  ┌─────┐ ┌─────┐  ┌──────────────────────────────────┐   │   │
│  │  │START │ │STOP │  │  Status: RUNNING                │   │   │
│  │  └─────┘ └─────┘  │  Symbol: XAUUSD_o               │   │   │
│  │                    │  Remote: XAUUSD                 │   │   │
│  │                    │  Profit: $1.25                  │   │   │
│  │                    │  Position: BUY                  │   │   │
│  │                    │  Ticket: 123456                │   │   │
│  │                    │  Diff: 35.0 pts                │   │   │
│  │                    │  Risk-Free: ACTIVE             │   │   │
│  │                    │  Trailing: $0.75               │   │   │
│  │                    └──────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 **پروتکل ارتباطی**

### **جریان داده**

| مرحله | فرستنده | گیرنده | پیام | توضیح |
|-------|---------|--------|------|-------|
| 1 | Slave | Master | `SYMBOL\|BID\|ASK\|TIMESTAMP` | ارسال قیمت لحظه‌ای + Heartbeat |
| 2 | Master | Slave | `ORDER\|CMD_ID\|TYPE\|SYMBOL\|LOT\|PRICE` | ارسال دستور معامله |
| 3 | Slave | Master | `SUCCESS\|TICKET` یا `ERROR\|CODE` | تأیید یا رد معامله |
| 4 | Master | Slave | `CLOSE\|CMD_ID` | دستور بستن معاملات |
| 5 | Slave | Master | `CLOSE_SUCCESS\|ALL` یا `ERROR\|CLOSE_FAILED` | تأیید بستن |
| 6 | Master | Slave | `STATUS\|CMD_ID` | درخواست وضعیت |
| 7 | Slave | Master | `STATUS\|HAS_POSITION\|TICKET` یا `STATUS\|NO_POSITION` | پاسخ وضعیت |

---

## 📁 **فایل‌های نهایی**

### **1. ArbitrageMaster.mq4 (سرور - LiteFinance)**

```mql4
//+------------------------------------------------------------------+
//|                                          ArbitrageMaster.mq4     |
//|                                          Arbitrage Server        |
//|                                          LiteFinance Broker      |
//|                                          Symbol: XAUUSD_o        |
//|                                          Version 6.3 FINAL       |
//+------------------------------------------------------------------+
#property copyright "Arbitrage System"
#property link      ""
#property version   "6.30"
#property strict

#include <Zmq/Zmq.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input string  InpSymbolLocal       = "XAUUSD_o";   // Local symbol (LiteFinance)
input string  InpSymbolRemote      = "XAUUSD";     // Remote symbol (OpoFinance)
input double  InpMinSpread         = 50.0;         // Min spread for entry (points)
input double  InpLotSize           = 0.01;         // Trade volume
input int     InpSlavePort         = 5556;         // REP port (Slave -> Master)
input int     InpMasterPort        = 5555;         // PULL port (Master <- Slave)
input int     InpSlippage          = 5;            // Allowed slippage
input int     InpMagic             = 5402;         // Magic number for positions
input int     InpCommandTimeout    = 5;            // Command timeout (seconds)

//+------------------------------------------------------------------+
//| RISK MANAGEMENT PARAMETERS                                       |
//+------------------------------------------------------------------+
input double  InpTakeProfit        = 2.0;          // Take profit ($)
input double  InpStopLoss          = 1.5;          // Stop loss ($)
input double  InpTrailingStart     = 1.0;          // Trailing start ($)
input double  InpTrailingStep      = 0.5;          // Trailing step ($)
input int     InpMaxTimeMinutes    = 5;            // Max time (minutes)
input double  InpRiskFreeThreshold = 0.5;          // Risk-free threshold ($)

//+------------------------------------------------------------------+
//| CONSTANTS                                                        |
//+------------------------------------------------------------------+
#define PREFIX          "ArbM_"
#define BTN_START       PREFIX + "Start"
#define BTN_STOP        PREFIX + "Stop"
#define TIMER_INTERVAL  50  // milliseconds

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
Context     *g_ctx = NULL;
Socket      *g_pull = NULL;          // PULL - receive prices from Slave
Socket      *g_req = NULL;           // REQ - send orders to Slave

double      g_bid = 0.0;
double      g_ask = 0.0;
double      g_slaveBid = 0.0;
double      g_slaveAsk = 0.0;

bool        g_socketReady = false;
bool        g_masterActive = false;   // Real active status based on heartbeat
bool        g_running = false;
bool        g_closing = false;
bool        g_shutdown = false;

datetime    g_lastUpdate = 0;
datetime    g_lastDisplay = 0;
datetime    g_lastPriceReceived = 0;
datetime    g_lastHeartbeat = 0;

int         g_ticket = -1;
bool        g_hasPos = false;
datetime    g_entryTime = 0;
double      g_entryPrice = 0.0;
int         g_orderType = -1;

double      g_highestProfit = 0.0;
double      g_trailingLevel = 0.0;
bool        g_riskFree = false;
double      g_profit = 0.0;
double      g_diff = 0.0;
int         g_timeMin = 0;

// State for REQ/REP communication
enum ENUM_REQ_STATE
{
    REQ_READY,
    REQ_WAITING_REPLY,
    REQ_RECONCILING
};

ENUM_REQ_STATE g_reqState = REQ_READY;
string        g_pendingCommand = "";
string        g_pendingCmdId = "";
datetime      g_lastReqTime = 0;
int           g_retryCount = 0;

//+------------------------------------------------------------------+
//| CREATE UI                                                        |
//+------------------------------------------------------------------+
void CreateUI()
{
    int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
    int x = w - 125;
    int y = 20;
    
    // START Button
    ObjectCreate(0, BTN_START, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, BTN_START, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, BTN_START, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, BTN_START, OBJPROP_XSIZE, 55);
    ObjectSetInteger(0, BTN_START, OBJPROP_YSIZE, 25);
    ObjectSetInteger(0, BTN_START, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, BTN_START, OBJPROP_BGCOLOR, clrLimeGreen);
    ObjectSetInteger(0, BTN_START, OBJPROP_COLOR, clrBlack);
    ObjectSetInteger(0, BTN_START, OBJPROP_BORDER_COLOR, clrDarkGreen);
    ObjectSetInteger(0, BTN_START, OBJPROP_BACK, true);
    ObjectSetInteger(0, BTN_START, OBJPROP_FONTSIZE, 9);
    ObjectSetString(0, BTN_START, OBJPROP_TEXT, "START");
    ObjectSetString(0, BTN_START, OBJPROP_FONT, "Arial");
    
    // STOP Button
    ObjectCreate(0, BTN_STOP, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_XDISTANCE, x + 60);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_XSIZE, 55);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_YSIZE, 25);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_BGCOLOR, clrRed);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_BORDER_COLOR, clrDarkRed);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_BACK, true);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_FONTSIZE, 9);
    ObjectSetString(0, BTN_STOP, OBJPROP_TEXT, "STOP");
    ObjectSetString(0, BTN_STOP, OBJPROP_FONT, "Arial");
    
    // Labels
    int y0 = 55;
    int step = 20;
    int x0 = 10;
    
    ObjectCreate(0, PREFIX + "Title", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Title", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Title", OBJPROP_YDISTANCE, y0);
    ObjectSetInteger(0, PREFIX + "Title", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Title", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Title", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Title", OBJPROP_TEXT, "=== ARBITRAGE MASTER v6.3 ===");
    ObjectSetString(0, PREFIX + "Title", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Status", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_YDISTANCE, y0 + step);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Status", OBJPROP_TEXT, "Status: READY");
    ObjectSetString(0, PREFIX + "Status", OBJPROP_FONT, "Arial");
    
    string lblSymbol = "Symbol: " + InpSymbolLocal;
    ObjectCreate(0, PREFIX + "Symbol", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Symbol", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Symbol", OBJPROP_YDISTANCE, y0 + step * 2);
    ObjectSetInteger(0, PREFIX + "Symbol", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Symbol", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Symbol", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Symbol", OBJPROP_TEXT, lblSymbol);
    ObjectSetString(0, PREFIX + "Symbol", OBJPROP_FONT, "Arial");
    
    string lblRemote = "Remote: " + InpSymbolRemote;
    ObjectCreate(0, PREFIX + "Remote", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Remote", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Remote", OBJPROP_YDISTANCE, y0 + step * 3);
    ObjectSetInteger(0, PREFIX + "Remote", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Remote", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Remote", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Remote", OBJPROP_TEXT, lblRemote);
    ObjectSetString(0, PREFIX + "Remote", OBJPROP_FONT, "Arial");
    
    string lblSpread = "Min Spread: " + DoubleToStr(InpMinSpread, 0) + " pts";
    ObjectCreate(0, PREFIX + "Spread", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Spread", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Spread", OBJPROP_YDISTANCE, y0 + step * 4);
    ObjectSetInteger(0, PREFIX + "Spread", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Spread", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Spread", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Spread", OBJPROP_TEXT, lblSpread);
    ObjectSetString(0, PREFIX + "Spread", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Profit", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_YDISTANCE, y0 + step * 5);
    ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Profit", OBJPROP_TEXT, "Profit: $0.00");
    ObjectSetString(0, PREFIX + "Profit", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Position", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Position", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Position", OBJPROP_YDISTANCE, y0 + step * 6);
    ObjectSetInteger(0, PREFIX + "Position", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Position", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Position", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Position", OBJPROP_TEXT, "Position: NONE");
    ObjectSetString(0, PREFIX + "Position", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Ticket", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Ticket", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Ticket", OBJPROP_YDISTANCE, y0 + step * 7);
    ObjectSetInteger(0, PREFIX + "Ticket", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Ticket", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Ticket", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Ticket", OBJPROP_TEXT, "Ticket: -");
    ObjectSetString(0, PREFIX + "Ticket", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Diff", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Diff", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Diff", OBJPROP_YDISTANCE, y0 + step * 8);
    ObjectSetInteger(0, PREFIX + "Diff", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Diff", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Diff", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Diff", OBJPROP_TEXT, "Diff: 0.0 pts");
    ObjectSetString(0, PREFIX + "Diff", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Time", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Time", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Time", OBJPROP_YDISTANCE, y0 + step * 9);
    ObjectSetInteger(0, PREFIX + "Time", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Time", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Time", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Time", OBJPROP_TEXT, "Time: 0 min");
    ObjectSetString(0, PREFIX + "Time", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "RiskFree", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "RiskFree", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "RiskFree", OBJPROP_YDISTANCE, y0 + step * 10);
    ObjectSetInteger(0, PREFIX + "RiskFree", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "RiskFree", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "RiskFree", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "RiskFree", OBJPROP_TEXT, "Risk-Free: OFF");
    ObjectSetString(0, PREFIX + "RiskFree", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Trailing", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Trailing", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Trailing", OBJPROP_YDISTANCE, y0 + step * 11);
    ObjectSetInteger(0, PREFIX + "Trailing", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Trailing", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Trailing", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Trailing", OBJPROP_TEXT, "Trailing: $0.00");
    ObjectSetString(0, PREFIX + "Trailing", OBJPROP_FONT, "Arial");
    
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| UPDATE DISPLAY                                                   |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
    string status;
    color clr;
    
    if(g_shutdown)
    {
        status = "SHUTDOWN";
        clr = clrRed;
    }
    else if(g_closing)
    {
        status = "CLOSING";
        clr = clrOrange;
    }
    else if(g_running && g_masterActive)
    {
        status = "RUNNING";
        clr = clrLimeGreen;
    }
    else if(g_running)
    {
        status = "CONNECTING";
        clr = clrYellow;
    }
    else if(g_socketReady)
    {
        status = "READY";
        clr = clrWhite;
    }
    else
    {
        status = "INIT";
        clr = clrGray;
    }
    
    ObjectSetString(0, PREFIX + "Status", OBJPROP_TEXT, "Status: " + status);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_COLOR, clr);
    
    ObjectSetString(0, PREFIX + "Profit", OBJPROP_TEXT, "Profit: $" + DoubleToStr(g_profit, 2));
    ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_COLOR, g_profit >= 0 ? clrLimeGreen : clrRed);
    
    if(g_hasPos)
    {
        string type = (g_orderType == OP_BUY) ? "BUY" : "SELL";
        ObjectSetString(0, PREFIX + "Position", OBJPROP_TEXT, "Position: " + type);
        ObjectSetInteger(0, PREFIX + "Position", OBJPROP_COLOR, clrYellow);
    }
    else
    {
        ObjectSetString(0, PREFIX + "Position", OBJPROP_TEXT, "Position: NONE");
        ObjectSetInteger(0, PREFIX + "Position", OBJPROP_COLOR, clrGray);
    }
    
    if(g_ticket > 0)
        ObjectSetString(0, PREFIX + "Ticket", OBJPROP_TEXT, "Ticket: " + IntegerToString(g_ticket));
    else
        ObjectSetString(0, PREFIX + "Ticket", OBJPROP_TEXT, "Ticket: -");
    
    ObjectSetString(0, PREFIX + "Diff", OBJPROP_TEXT, "Diff: " + DoubleToStr(g_diff, 1) + " pts");
    ObjectSetInteger(0, PREFIX + "Diff", OBJPROP_COLOR, g_diff >= InpMinSpread ? clrLimeGreen : clrGray);
    
    ObjectSetString(0, PREFIX + "Time", OBJPROP_TEXT, "Time: " + IntegerToString(g_timeMin) + " min");
    
    if(g_riskFree)
    {
        ObjectSetString(0, PREFIX + "RiskFree", OBJPROP_TEXT, "Risk-Free: ACTIVE");
        ObjectSetInteger(0, PREFIX + "RiskFree", OBJPROP_COLOR, clrLimeGreen);
    }
    else
    {
        ObjectSetString(0, PREFIX + "RiskFree", OBJPROP_TEXT, "Risk-Free: OFF");
        ObjectSetInteger(0, PREFIX + "RiskFree", OBJPROP_COLOR, clrGray);
    }
    
    if(g_trailingLevel > 0)
    {
        ObjectSetString(0, PREFIX + "Trailing", OBJPROP_TEXT, "Trailing: $" + DoubleToStr(g_trailingLevel, 2));
        ObjectSetInteger(0, PREFIX + "Trailing", OBJPROP_COLOR, clrYellow);
    }
    else
    {
        ObjectSetString(0, PREFIX + "Trailing", OBJPROP_TEXT, "Trailing: $0.00");
        ObjectSetInteger(0, PREFIX + "Trailing", OBJPROP_COLOR, clrGray);
    }
    
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| SYNC STATE FROM ORDERS                                           |
//+------------------------------------------------------------------+
void SyncStateFromOrders()
{
    g_hasPos = false;
    g_ticket = -1;
    g_profit = 0.0;
    
    int total = OrdersTotal();
    for(int i = total - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == InpSymbolLocal && OrderMagicNumber() == InpMagic)
            {
                g_hasPos = true;
                g_ticket = OrderTicket();
                g_orderType = OrderType();
                g_entryPrice = OrderOpenPrice();
                g_profit = OrderProfit() + OrderSwap() + OrderCommission();
                g_entryTime = OrderOpenTime();
                return;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| GENERATE COMMAND ID                                              |
//+------------------------------------------------------------------+
string GenerateCmdId()
{
    return IntegerToString(TimeCurrent()) + "_" + IntegerToString(rand());
}

//+------------------------------------------------------------------+
//| INITIALIZE ZMQ                                                   |
//+------------------------------------------------------------------+
bool InitZMQ()
{
    CleanupZMQ();
    
    g_ctx = new Context("arbitrage_master");
    if(g_ctx == NULL)
    {
        Print("Failed to create ZMQ context");
        return false;
    }
    
    g_pull = new Socket(g_ctx, ZMQ_PULL);
    if(g_pull == NULL)
    {
        Print("Failed to create PULL socket");
        CleanupZMQ();
        return false;
    }
    
    string pullAddr = StringFormat("tcp://*:%d", InpMasterPort);
    if(!g_pull.bind(pullAddr))
    {
        Print("Cannot bind PULL port ", InpMasterPort);
        CleanupZMQ();
        return false;
    }
    Print("PULL bound: ", InpMasterPort);
    
    g_req = new Socket(g_ctx, ZMQ_REQ);
    if(g_req == NULL)
    {
        Print("Failed to create REQ socket");
        CleanupZMQ();
        return false;
    }
    
    string reqAddr = StringFormat("tcp://*:%d", InpSlavePort);
    if(!g_req.bind(reqAddr))
    {
        Print("Cannot bind REQ port ", InpSlavePort);
        CleanupZMQ();
        return false;
    }
    Print("REQ bound: ", InpSlavePort);
    
    g_socketReady = true;
    g_masterActive = false;
    g_reqState = REQ_READY;
    g_lastHeartbeat = TimeCurrent();
    return true;
}

//+------------------------------------------------------------------+
//| CLEANUP ZMQ                                                      |
//+------------------------------------------------------------------+
void CleanupZMQ()
{
    if(g_pull != NULL) { delete g_pull; g_pull = NULL; }
    if(g_req != NULL) { delete g_req; g_req = NULL; }
    if(g_ctx != NULL) { delete g_ctx; g_ctx = NULL; }
    g_socketReady = false;
    g_masterActive = false;
    g_reqState = REQ_READY;
}

//+------------------------------------------------------------------+
//| SAFE START                                                       |
//+------------------------------------------------------------------+
void SafeStart()
{
    if(g_running)
    {
        Print("Already running!");
        return;
    }
    
    Print("========================================");
    Print("  SAFE START");
    Print("========================================");
    
    if(!InitZMQ())
    {
        Print("ZMQ init failed!");
        return;
    }
    
    SyncStateFromOrders();
    
    g_running = true;
    g_shutdown = false;
    g_closing = false;
    g_masterActive = false;
    g_lastHeartbeat = TimeCurrent();
    UpdateDisplay();
    Print("✅ Started!");
    Print("========================================");
    
    EventSetMillisecondTimer(TIMER_INTERVAL);
}

//+------------------------------------------------------------------+
//| SAFE STOP                                                        |
//+------------------------------------------------------------------+
void SafeStop()
{
    if(!g_running && !g_socketReady)
    {
        Print("Already stopped!");
        return;
    }
    
    Print("========================================");
    Print("  SAFE STOP");
    Print("========================================");
    
    EventKillTimer();
    
    g_shutdown = true;
    
    // Close positions BEFORE setting g_closing
    if(g_hasPos)
    {
        Print("Closing positions...");
        CloseAllPositions();
    }
    
    g_closing = true;
    CleanupZMQ();
    
    g_running = false;
    g_closing = false;
    g_shutdown = false;
    UpdateDisplay();
    Print("✅ Stopped!");
    Print("========================================");
}

//+------------------------------------------------------------------+
//| CLOSE TICKET WITH RETRY                                          |
//+------------------------------------------------------------------+
bool CloseTicketWithRetry(int ticket, int attempts = 3)
{
    for(int i = 0; i < attempts; i++)
    {
        if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
            return true;
        
        // Only market orders
        if(OrderType() != OP_BUY && OrderType() != OP_SELL)
        {
            if(OrderDelete(ticket))
                return true;
            else
            {
                Print("Delete failed: ", GetLastError());
                continue;
            }
        }
        
        RefreshRates();
        
        double closePrice = (OrderType() == OP_BUY) ? MarketInfo(OrderSymbol(), MODE_BID) 
                                                     : MarketInfo(OrderSymbol(), MODE_ASK);
        
        if(closePrice <= 0)
        {
            Sleep(100);
            continue;
        }
        
        ResetLastError();
        
        if(OrderClose(ticket, OrderLots(), closePrice, InpSlippage, clrNONE))
        {
            Print("✅ Closed: ", ticket);
            return true;
        }
        
        int err = GetLastError();
        Print("Close retry ", i+1, " failed. Ticket=", ticket, " Error=", err);
        
        if(err == 146) Sleep(200); // trade context busy
        else Sleep(100);
    }
    
    Print("❌ Failed to close ticket ", ticket);
    return false;
}

//+------------------------------------------------------------------+
//| CLOSE ALL POSITIONS                                              |
//+------------------------------------------------------------------+
bool CloseAllPositions()
{
    if(g_closing || !g_hasPos) return true;
    
    g_closing = true;
    bool slaveClosed = false;
    bool masterClosed = false;
    bool needReconcile = false;
    
    // Send CLOSE to Slave FIRST (parallel execution)
    if(g_req != NULL && g_socketReady && g_reqState == REQ_READY)
    {
        string cmdId = GenerateCmdId();
        Print("Sending CLOSE to Slave... (", cmdId, ")");
        
        if(SendCommandWithRetry("CLOSE|" + cmdId))
        {
            Print("✅ CLOSE sent to Slave");
            slaveClosed = true;
        }
        else
        {
            Print("❌ Failed to send CLOSE to Slave!");
            needReconcile = true;
        }
    }
    
    // If we need reconciliation, check STATUS
    if(needReconcile && g_req != NULL && g_socketReady && g_reqState == REQ_READY)
    {
        Print("Reconciling: Checking Slave STATUS...");
        string statusCmd = "STATUS|" + GenerateCmdId();
        
        if(SendCommandWithRetry(statusCmd))
        {
            Print("Reconciliation complete.");
        }
    }
    
    // Then close Master
    if(g_ticket > 0)
    {
        masterClosed = CloseTicketWithRetry(g_ticket, 3);
    }
    else
    {
        masterClosed = true;
    }
    
    g_hasPos = false;
    g_ticket = -1;
    g_entryTime = 0;
    g_highestProfit = 0;
    g_trailingLevel = 0;
    g_riskFree = false;
    g_closing = false;
    
    SyncStateFromOrders();
    
    if(masterClosed && (slaveClosed || !needReconcile))
    {
        Print("✅ All positions closed successfully!");
        return true;
    }
    else
    {
        Print("⚠️ CRITICAL: Positions may not be fully closed!");
        Alert("⚠️ CRITICAL: Arbitrage positions mismatch detected!");
        return false;
    }
}

//+------------------------------------------------------------------+
//| SEND COMMAND WITH RETRY                                          |
//+------------------------------------------------------------------+
bool SendCommandWithRetry(string command)
{
    if(g_req == NULL || !g_socketReady || g_reqState != REQ_READY)
        return false;
    
    g_pendingCommand = command;
    g_reqState = REQ_WAITING_REPLY;
    g_lastReqTime = TimeCurrent();
    g_retryCount = 0;
    
    Print("📤 Sending: ", command);
    
    if(!g_req.send(ZmqMsg(command)))
    {
        g_reqState = REQ_READY;
        Print("❌ Failed to send!");
        return false;
    }
    
    // Non-blocking wait for response
    datetime startTime = TimeCurrent();
    int maxAttempts = InpCommandTimeout * 20; // 20 checks per second
    
    while(TimeCurrent() - startTime < InpCommandTimeout)
    {
        Sleep(20);
        ZmqMsg reply;
        if(g_req.recv(reply, false))
        {
            string response = reply.getData();
            Print("📨 Response: ", response);
            
            if(StringFind(response, "SUCCESS") >= 0 ||
               StringFind(response, "STATUS|HAS_POSITION") >= 0 ||
               StringFind(response, "STATUS|NO_POSITION") >= 0)
            {
                g_reqState = REQ_READY;
                return true;
            }
            else
            {
                Print("❌ Error: ", response);
                g_reqState = REQ_READY;
                return false;
            }
        }
        
        g_retryCount++;
    }
    
    Print("⏰ Timeout for: ", command);
    g_reqState = REQ_READY;
    return false;
}

//+------------------------------------------------------------------+
//| CHECK EXIT CONDITIONS                                            |
//+------------------------------------------------------------------+
void CheckExit()
{
    if(!g_hasPos || g_ticket <= 0 || g_closing) return;
    
    if(OrderSelect(g_ticket, SELECT_BY_TICKET, MODE_TRADES))
    {
        g_profit = OrderProfit() + OrderSwap() + OrderCommission();
    }
    else
    {
        g_hasPos = false;
        g_ticket = -1;
        return;
    }
    
    g_timeMin = (int)((TimeCurrent() - g_entryTime) / 60);
    
    if(g_profit > g_highestProfit) g_highestProfit = g_profit;
    
    // Risk-Free activation
    if(g_profit >= InpRiskFreeThreshold && !g_riskFree)
    {
        g_riskFree = true;
        Print("🛡️ RISK-FREE ACTIVATED! Profit: $", DoubleToStr(g_profit, 2));
    }
    
    // Trailing Stop
    if(g_profit >= InpTrailingStart && g_riskFree)
    {
        double newLevel = g_profit - InpTrailingStep;
        if(newLevel > g_trailingLevel)
        {
            g_trailingLevel = newLevel;
            Print("📈 Trailing Level: $", DoubleToStr(g_trailingLevel, 2));
        }
    }
    
    // ===== EXIT CONDITIONS =====
    
    if(g_profit >= InpTakeProfit)
    {
        Print("💰 TAKE PROFIT: $", DoubleToStr(g_profit, 2));
        CloseAllPositions();
        return;
    }
    
    if(g_riskFree && g_trailingLevel > 0 && g_profit <= g_trailingLevel)
    {
        Print("📉 TRAILING STOP: $", DoubleToStr(g_profit, 2));
        CloseAllPositions();
        return;
    }
    
    if(!g_riskFree && g_profit <= -InpStopLoss)
    {
        Print("⛔ STOP LOSS: $", DoubleToStr(g_profit, 2));
        CloseAllPositions();
        return;
    }
    
    if(g_timeMin >= InpMaxTimeMinutes)
    {
        Print("⏰ Time limit: ", g_timeMin, " min");
        CloseAllPositions();
        return;
    }
}

//+------------------------------------------------------------------+
//| CHECK OPPORTUNITY                                                |
//+------------------------------------------------------------------+
void CheckOpportunity()
{
    // Don't check if slave not active
    if(!g_masterActive)
    {
        if(TimeCurrent() - g_lastHeartbeat > 3)
        {
            // Still waiting for heartbeat
        }
        return;
    }
    
    // Don't use stale prices (older than 1 second)
    if(TimeCurrent() - g_lastPriceReceived > 1)
        return;
    
    if(g_slaveBid == 0 || g_slaveAsk == 0 || g_closing || g_hasPos) return;
    
    int digits = (int)MarketInfo(InpSymbolLocal, MODE_DIGITS);
    double point = MarketInfo(InpSymbolLocal, MODE_POINT);
    
    if(point <= 0)
    {
        Print("ERROR: Invalid point value for ", InpSymbolLocal);
        return;
    }
    
    g_diff = MathAbs(g_bid - g_slaveBid) / point;
    
    if(g_diff >= InpMinSpread)
    {
        if(g_bid < g_slaveBid)
        {
            Print("🎯 OPPORTUNITY: Buy Local, Sell Remote (Diff: ", DoubleToStr(g_diff, 0), " pts)");
            Execute(OP_BUY, OP_SELL);
        }
        else if(g_bid > g_slaveBid)
        {
            Print("🎯 OPPORTUNITY: Sell Local, Buy Remote (Diff: ", DoubleToStr(g_diff, 0), " pts)");
            Execute(OP_SELL, OP_BUY);
        }
    }
}

//+------------------------------------------------------------------+
//| EXECUTE TRADE                                                    |
//+------------------------------------------------------------------+
void Execute(int localType, int slaveType)
{
    if(g_closing || g_hasPos || g_shutdown) return;
    
    RefreshRates();
    
    int digits = (int)MarketInfo(InpSymbolLocal, MODE_DIGITS);
    double price = (localType == OP_BUY) ? MarketInfo(InpSymbolLocal, MODE_ASK) 
                                         : MarketInfo(InpSymbolLocal, MODE_BID);
    
    if(price <= 0)
    {
        Print("ERROR: Invalid price for ", InpSymbolLocal);
        return;
    }
    
    int err = OrderSend(InpSymbolLocal, localType, InpLotSize, price, InpSlippage, 
                        0, 0, "Arbitrage A", InpMagic, 0, clrNONE);
    
    if(err > 0)
    {
        g_ticket = err;
        g_entryPrice = price;
        g_orderType = localType;
        g_entryTime = TimeCurrent();
        g_hasPos = true;
        g_highestProfit = 0;
        g_trailingLevel = 0;
        g_riskFree = false;
        g_profit = 0;
        Print("✅ Trade opened: ", g_ticket);
        Print("   Entry: ", TimeToString(g_entryTime));
        Print("   Type: ", (localType == OP_BUY) ? "BUY" : "SELL");
        Print("   Price: ", DoubleToStr(price, digits));
        
        // Send order to Slave with command ID
        string cmdId = GenerateCmdId();
        string orderTypeStr = (slaveType == OP_BUY) ? "BUY" : "SELL";
        double slavePrice = (slaveType == OP_BUY) ? g_slaveAsk : g_slaveBid;
        string cmd = StringFormat("ORDER|%s|%s|%s|%.2f|%.5f", 
                                  cmdId, orderTypeStr, InpSymbolRemote, InpLotSize, slavePrice);
        
        if(!SendCommandWithRetry(cmd))
        {
            Print("❌ CRITICAL: Failed to send order to Slave! Closing Master...");
            
            // Try to reconcile - check if Slave actually got the order
            string statusCmd = "STATUS|" + GenerateCmdId();
            if(SendCommandWithRetry(statusCmd))
            {
                // Check response - handled in SendCommandWithRetry
                // If slave has position, we shouldn't close master
                SyncStateFromOrders();
                if(g_hasPos)
                {
                    Print("⚠️ Slave has position but Master also has position. Manual intervention required!");
                    Alert("⚠️ ARBITRAGE MISMATCH! Both sides may have positions!");
                    return;
                }
            }
            
            if(!CloseTicketWithRetry(g_ticket, 5))
            {
                Print("⚠️ CRITICAL: Failed to close Master position! Manual intervention required!");
                Alert("⚠️ CRITICAL: Unhedged position detected! Manual intervention required!");
            }
            g_hasPos = false;
        }
    }
    else
    {
        Print("❌ Error opening trade: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| ONINIT                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("  ARBITRAGE MASTER v6.3 FINAL");
    Print("========================================");
    Print("Local: ", InpSymbolLocal);
    Print("Remote: ", InpSymbolRemote);
    Print("Magic: ", InpMagic);
    Print("Command Timeout: ", InpCommandTimeout, "s");
    Print("========================================");
    
    // Validate symbol
    double testBid = MarketInfo(InpSymbolLocal, MODE_BID);
    if(testBid <= 0)
    {
        Print("ERROR: Symbol ", InpSymbolLocal, " not found or invalid!");
        Print("Please check symbol name and Market Watch");
        return INIT_FAILED;
    }
    Print("Symbol validation: Bid=", DoubleToStr(testBid, (int)MarketInfo(InpSymbolLocal, MODE_DIGITS)));
    Print("========================================");
    
    CreateUI();
    UpdateDisplay();
    SyncStateFromOrders();
    
    if(g_hasPos)
    {
        Print("⚠️ Existing position detected! Ticket: ", g_ticket);
    }
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| ONTIMER                                                          |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(!g_running || g_closing || g_shutdown) return;
    
    // Update prices
    g_bid = MarketInfo(InpSymbolLocal, MODE_BID);
    g_ask = MarketInfo(InpSymbolLocal, MODE_ASK);
    g_lastUpdate = TimeCurrent();
    
    if(g_bid <= 0 || g_ask <= 0) return;
    
    // Receive slave price (PULL socket) - DRAIN ALL MESSAGES
    if(g_pull != NULL)
    {
        string latestData = "";
        ZmqMsg req;
        
        while(g_pull.recv(req, false))
        {
            latestData = req.getData();
        }
        
        if(latestData != "")
        {
            string parts[];
            int cnt = StringSplit(latestData, '|', parts);
            if(cnt >= 3)
            {
                g_slaveBid = StringToDouble(parts[1]);
                g_slaveAsk = StringToDouble(parts[2]);
                g_lastPriceReceived = TimeCurrent();
                g_lastHeartbeat = TimeCurrent();
                g_masterActive = true;
            }
        }
    }
    
    // Check if slave is still active (heartbeat)
    if(TimeCurrent() - g_lastHeartbeat > 3)
    {
        g_masterActive = false;
    }
    
    // Check REQ state for responses
    if(g_req != NULL && g_reqState == REQ_WAITING_REPLY)
    {
        ZmqMsg reply;
        if(g_req.recv(reply, false))
        {
            string response = reply.getData();
            Print("📨 Response: ", response);
            
            if(StringFind(response, "SUCCESS") >= 0 || 
               StringFind(response, "STATUS|") >= 0)
            {
                g_reqState = REQ_READY;
            }
            else
            {
                Print("❌ Error response: ", response);
                g_reqState = REQ_READY;
            }
        }
        else if(TimeCurrent() - g_lastReqTime > InpCommandTimeout)
        {
            Print("⏰ REQ timeout! Resetting socket...");
            g_reqState = REQ_READY;
            
            if(g_req != NULL)
            {
                delete g_req;
                g_req = new Socket(g_ctx, ZMQ_REQ);
                if(g_req != NULL)
                {
                    string reqAddr = StringFormat("tcp://*:%d", InpSlavePort);
                    g_req.bind(reqAddr);
                    Print("REQ socket reset");
                }
            }
        }
    }
    
    if(g_hasPos) CheckExit();
    else CheckOpportunity();
    
    if(TimeCurrent() - g_lastDisplay >= 1)
    {
        UpdateDisplay();
        g_lastDisplay = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| ONTICK                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
    // Timer handles all main logic
    // Sync state on tick to ensure positions are tracked
    if(g_running && !g_shutdown && !g_closing)
    {
        SyncStateFromOrders();
    }
}

//+------------------------------------------------------------------+
//| ONCHARTEVENT                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(sparam == BTN_START)
        {
            Print("START button clicked");
            SafeStart();
            ObjectSetInteger(0, BTN_START, OBJPROP_STATE, false);
            ChartRedraw(0);
        }
        else if(sparam == BTN_STOP)
        {
            Print("STOP button clicked");
            SafeStop();
            ObjectSetInteger(0, BTN_STOP, OBJPROP_STATE, false);
            ChartRedraw(0);
        }
    }
    
    if(id == CHARTEVENT_KEYDOWN)
    {
        if(sparam == "S" || sparam == "s") SafeStart();
        else if(sparam == "X" || sparam == "x") SafeStop();
    }
}

//+------------------------------------------------------------------+
//| ONDEINIT                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    
    if(g_running || g_socketReady) SafeStop();
    
    ObjectDelete(0, BTN_START);
    ObjectDelete(0, BTN_STOP);
    ObjectDelete(0, PREFIX + "Title");
    ObjectDelete(0, PREFIX + "Status");
    ObjectDelete(0, PREFIX + "Symbol");
    ObjectDelete(0, PREFIX + "Remote");
    ObjectDelete(0, PREFIX + "Spread");
    ObjectDelete(0, PREFIX + "Profit");
    ObjectDelete(0, PREFIX + "Position");
    ObjectDelete(0, PREFIX + "Ticket");
    ObjectDelete(0, PREFIX + "Diff");
    ObjectDelete(0, PREFIX + "Time");
    ObjectDelete(0, PREFIX + "RiskFree");
    ObjectDelete(0, PREFIX + "Trailing");
    ChartRedraw(0);
    Print("Master stopped.");
}
//+------------------------------------------------------------------+
```

---

### **2. ArbitrageSlave.mq4 (کلاینت - OpoFinance)**

```mql4
//+------------------------------------------------------------------+
//|                                          ArbitrageSlave.mq4      |
//|                                          Arbitrage Client        |
//|                                          OpoFinance Broker       |
//|                                          Symbol: XAUUSD          |
//|                                          Version 6.3 FINAL       |
//+------------------------------------------------------------------+
#property copyright "Arbitrage System"
#property link      ""
#property version   "6.30"
#property strict

#include <Zmq/Zmq.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input string  InpMasterIP          = "127.0.0.1";
input int     InpMasterPubPort     = 5555;          // PULL port (Master <- Slave)
input int     InpMasterRepPort     = 5556;          // REQ port (Master -> Slave)
input string  InpSymbolLocal       = "XAUUSD";
input double  InpLotSize           = 0.01;
input int     InpSlippage          = 5;
input int     InpMagic             = 5402;

//+------------------------------------------------------------------+
//| CONSTANTS                                                        |
//+------------------------------------------------------------------+
#define PREFIX          "ArbS_"
#define BTN_START       PREFIX + "Start"
#define BTN_STOP        PREFIX + "Stop"
#define TIMER_INTERVAL  50  // milliseconds

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
Context     *g_ctx = NULL;
Socket      *g_push = NULL;          // PUSH - send prices to Master
Socket      *g_rep = NULL;           // REP - receive orders from Master

double      g_bid = 0.0;
double      g_ask = 0.0;

bool        g_socketReady = false;
bool        g_masterActive = false;
bool        g_running = false;
bool        g_closing = false;
bool        g_shutdown = false;

datetime    g_lastUpdate = 0;
datetime    g_lastSend = 0;
datetime    g_lastDisplay = 0;
datetime    g_lastHeartbeat = 0;

double      g_lastSentBid = 0.0;
double      g_lastSentAsk = 0.0;

int         g_ticket = -1;
bool        g_hasPos = false;
double      g_profit = 0.0;

// Command cache for idempotency
string      g_lastCmdId = "";
string      g_lastCmdResponse = "";

//+------------------------------------------------------------------+
//| CREATE UI                                                        |
//+------------------------------------------------------------------+
void CreateUI()
{
    int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
    int x = w - 125;
    int y = 20;
    
    // START Button
    ObjectCreate(0, BTN_START, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, BTN_START, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, BTN_START, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, BTN_START, OBJPROP_XSIZE, 55);
    ObjectSetInteger(0, BTN_START, OBJPROP_YSIZE, 25);
    ObjectSetInteger(0, BTN_START, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, BTN_START, OBJPROP_BGCOLOR, clrLimeGreen);
    ObjectSetInteger(0, BTN_START, OBJPROP_COLOR, clrBlack);
    ObjectSetInteger(0, BTN_START, OBJPROP_BORDER_COLOR, clrDarkGreen);
    ObjectSetInteger(0, BTN_START, OBJPROP_BACK, true);
    ObjectSetInteger(0, BTN_START, OBJPROP_FONTSIZE, 9);
    ObjectSetString(0, BTN_START, OBJPROP_TEXT, "START");
    ObjectSetString(0, BTN_START, OBJPROP_FONT, "Arial");
    
    // STOP Button
    ObjectCreate(0, BTN_STOP, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_XDISTANCE, x + 60);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_XSIZE, 55);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_YSIZE, 25);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_BGCOLOR, clrRed);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_BORDER_COLOR, clrDarkRed);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_BACK, true);
    ObjectSetInteger(0, BTN_STOP, OBJPROP_FONTSIZE, 9);
    ObjectSetString(0, BTN_STOP, OBJPROP_TEXT, "STOP");
    ObjectSetString(0, BTN_STOP, OBJPROP_FONT, "Arial");
    
    // Labels
    int y0 = 55;
    int step = 20;
    int x0 = 10;
    
    ObjectCreate(0, PREFIX + "Title", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Title", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Title", OBJPROP_YDISTANCE, y0);
    ObjectSetInteger(0, PREFIX + "Title", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Title", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Title", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Title", OBJPROP_TEXT, "=== ARBITRAGE SLAVE v6.3 ===");
    ObjectSetString(0, PREFIX + "Title", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Status", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_YDISTANCE, y0 + step);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Status", OBJPROP_TEXT, "Status: READY");
    ObjectSetString(0, PREFIX + "Status", OBJPROP_FONT, "Arial");
    
    string lblSymbol = "Symbol: " + InpSymbolLocal;
    ObjectCreate(0, PREFIX + "Symbol", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Symbol", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Symbol", OBJPROP_YDISTANCE, y0 + step * 2);
    ObjectSetInteger(0, PREFIX + "Symbol", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Symbol", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Symbol", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Symbol", OBJPROP_TEXT, lblSymbol);
    ObjectSetString(0, PREFIX + "Symbol", OBJPROP_FONT, "Arial");
    
    string lblServer = "Server: " + InpMasterIP;
    ObjectCreate(0, PREFIX + "Server", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Server", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Server", OBJPROP_YDISTANCE, y0 + step * 3);
    ObjectSetInteger(0, PREFIX + "Server", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Server", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Server", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Server", OBJPROP_TEXT, lblServer);
    ObjectSetString(0, PREFIX + "Server", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Connected", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Connected", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Connected", OBJPROP_YDISTANCE, y0 + step * 4);
    ObjectSetInteger(0, PREFIX + "Connected", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Connected", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Connected", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Connected", OBJPROP_TEXT, "Connected: NO");
    ObjectSetString(0, PREFIX + "Connected", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Position", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Position", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Position", OBJPROP_YDISTANCE, y0 + step * 5);
    ObjectSetInteger(0, PREFIX + "Position", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Position", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Position", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Position", OBJPROP_TEXT, "Position: NONE");
    ObjectSetString(0, PREFIX + "Position", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Ticket", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Ticket", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Ticket", OBJPROP_YDISTANCE, y0 + step * 6);
    ObjectSetInteger(0, PREFIX + "Ticket", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Ticket", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Ticket", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Ticket", OBJPROP_TEXT, "Ticket: -");
    ObjectSetString(0, PREFIX + "Ticket", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Profit", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_YDISTANCE, y0 + step * 7);
    ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Profit", OBJPROP_TEXT, "Profit: $0.00");
    ObjectSetString(0, PREFIX + "Profit", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Bid", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Bid", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Bid", OBJPROP_YDISTANCE, y0 + step * 8);
    ObjectSetInteger(0, PREFIX + "Bid", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Bid", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Bid", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Bid", OBJPROP_TEXT, "Bid: 0.00000");
    ObjectSetString(0, PREFIX + "Bid", OBJPROP_FONT, "Arial");
    
    ObjectCreate(0, PREFIX + "Ask", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Ask", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Ask", OBJPROP_YDISTANCE, y0 + step * 9);
    ObjectSetInteger(0, PREFIX + "Ask", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Ask", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Ask", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, PREFIX + "Ask", OBJPROP_TEXT, "Ask: 0.00000");
    ObjectSetString(0, PREFIX + "Ask", OBJPROP_FONT, "Arial");
    
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| UPDATE DISPLAY                                                   |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
    string status;
    color clr;
    
    if(g_shutdown)
    {
        status = "SHUTDOWN";
        clr = clrRed;
    }
    else if(g_closing)
    {
        status = "CLOSING";
        clr = clrOrange;
    }
    else if(g_running && g_masterActive)
    {
        status = "RUNNING";
        clr = clrLimeGreen;
    }
    else if(g_running)
    {
        status = "CONNECTING";
        clr = clrYellow;
    }
    else if(g_socketReady)
    {
        status = "READY";
        clr = clrWhite;
    }
    else
    {
        status = "INIT";
        clr = clrGray;
    }
    
    ObjectSetString(0, PREFIX + "Status", OBJPROP_TEXT, "Status: " + status);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_COLOR, clr);
    
    ObjectSetString(0, PREFIX + "Connected", OBJPROP_TEXT, "Connected: " + (g_socketReady ? "YES" : "NO"));
    ObjectSetInteger(0, PREFIX + "Connected", OBJPROP_COLOR, g_socketReady ? clrLimeGreen : clrRed);
    
    if(g_hasPos)
    {
        ObjectSetString(0, PREFIX + "Position", OBJPROP_TEXT, "Position: OPEN");
        ObjectSetInteger(0, PREFIX + "Position", OBJPROP_COLOR, clrYellow);
    }
    else
    {
        ObjectSetString(0, PREFIX + "Position", OBJPROP_TEXT, "Position: NONE");
        ObjectSetInteger(0, PREFIX + "Position", OBJPROP_COLOR, clrGray);
    }
    
    if(g_ticket > 0)
        ObjectSetString(0, PREFIX + "Ticket", OBJPROP_TEXT, "Ticket: " + IntegerToString(g_ticket));
    else
        ObjectSetString(0, PREFIX + "Ticket", OBJPROP_TEXT, "Ticket: -");
    
    ObjectSetString(0, PREFIX + "Profit", OBJPROP_TEXT, "Profit: $" + DoubleToStr(g_profit, 2));
    ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_COLOR, g_profit >= 0 ? clrLimeGreen : clrRed);
    
    int digits = (int)MarketInfo(InpSymbolLocal, MODE_DIGITS);
    ObjectSetString(0, PREFIX + "Bid", OBJPROP_TEXT, "Bid: " + DoubleToStr(g_bid, digits));
    ObjectSetString(0, PREFIX + "Ask", OBJPROP_TEXT, "Ask: " + DoubleToStr(g_ask, digits));
    
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| SYNC STATE FROM ORDERS                                           |
//+------------------------------------------------------------------+
void SyncStateFromOrders()
{
    g_hasPos = false;
    g_ticket = -1;
    g_profit = 0.0;
    
    int total = OrdersTotal();
    for(int i = total - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == InpSymbolLocal && OrderMagicNumber() == InpMagic)
            {
                g_hasPos = true;
                g_ticket = OrderTicket();
                g_profit = OrderProfit() + OrderSwap() + OrderCommission();
                return;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| SEND RESPONSE to Master via REP                                  |
//+------------------------------------------------------------------+
bool SendResponse(string resp)
{
    if(g_rep == NULL || !g_socketReady)
    {
        Print("Cannot send response - REP disconnected: ", resp);
        return false;
    }
    
    Print("📤 Sending response: ", resp);
    
    if(!g_rep.send(ZmqMsg(resp)))
    {
        Print("❌ Failed to send response: ", resp);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| CLOSE TICKET WITH RETRY                                          |
//+------------------------------------------------------------------+
bool CloseTicketWithRetry(int ticket, int attempts = 3)
{
    for(int i = 0; i < attempts; i++)
    {
        if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
            return true;
        
        if(OrderType() != OP_BUY && OrderType() != OP_SELL)
            continue;
        
        RefreshRates();
        
        double closePrice = (OrderType() == OP_BUY) ? MarketInfo(OrderSymbol(), MODE_BID) 
                                                     : MarketInfo(OrderSymbol(), MODE_ASK);
        
        if(closePrice <= 0)
        {
            Sleep(100);
            continue;
        }
        
        ResetLastError();
        
        if(OrderClose(ticket, OrderLots(), closePrice, InpSlippage, clrNONE))
        {
            Print("✅ Closed: ", ticket);
            return true;
        }
        
        int err = GetLastError();
        Print("Close retry ", i+1, " failed. Ticket=", ticket, " Error=", err);
        
        if(err == 146) Sleep(200);
        else Sleep(100);
    }
    
    Print("❌ Failed to close ticket ", ticket);
    return false;
}

//+------------------------------------------------------------------+
//| CLOSE ALL ORDERS                                                 |
//+------------------------------------------------------------------+
bool CloseAllOrders()
{
    if(g_closing) return false;
    
    g_closing = true;
    
    int total = OrdersTotal();
    int matched = 0;
    int closed = 0;
    int failed = 0;
    
    RefreshRates();
    
    for(int i = total - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == InpSymbolLocal && OrderMagicNumber() == InpMagic)
            {
                if(OrderType() != OP_BUY && OrderType() != OP_SELL)
                    continue;
                
                matched++;
                
                if(CloseTicketWithRetry(OrderTicket(), 3))
                    closed++;
                else
                    failed++;
            }
        }
    }
    
    g_closing = false;
    SyncStateFromOrders();
    
    if(matched == 0)
    {
        Print("No positions to close.");
        return true;
    }
    
    if(failed == 0)
    {
        Print("✅ Closed ", closed, " positions successfully.");
        return true;
    }
    else
    {
        Print("⚠️ Closed ", closed, " positions, ", failed, " failed.");
        return false;
    }
}

//+------------------------------------------------------------------+
//| PRICE PROTECTION CHECK                                           |
//+------------------------------------------------------------------+
bool PriceProtection(string symbol, double requestedPrice, int orderType)
{
    RefreshRates();
    
    double currentPrice = (orderType == OP_BUY) ? MarketInfo(symbol, MODE_ASK) 
                                                : MarketInfo(symbol, MODE_BID);
    
    if(currentPrice <= 0)
    {
        Print("❌ Invalid current price for ", symbol);
        return false;
    }
    
    double point = MarketInfo(symbol, MODE_POINT);
    if(point <= 0)
    {
        Print("❌ Invalid point value for ", symbol);
        return false;
    }
    
    double maxDeviation = InpSlippage * point;
    int digits = (int)MarketInfo(symbol, MODE_DIGITS);
    
    if(MathAbs(currentPrice - requestedPrice) > maxDeviation)
    {
        Print("⚠️ Price changed! Requested: ", DoubleToStr(requestedPrice, digits),
              " Current: ", DoubleToStr(currentPrice, digits));
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| PROCESS COMMAND                                                  |
//+------------------------------------------------------------------+
void ProcessCommand(string cmd)
{
    if(g_shutdown)
    {
        SendResponse("ERROR|SYSTEM_SHUTDOWN");
        return;
    }
    
    if(g_closing)
    {
        SendResponse("ERROR|SYSTEM_CLOSING");
        return;
    }
    
    Print("Processing: ", cmd);
    
    string parts[];
    int cnt = StringSplit(cmd, '|', parts);
    if(cnt < 1)
    {
        SendResponse("ERROR|INVALID_FORMAT");
        return;
    }
    
    // Check for ORDER command
    if(parts[0] == "ORDER")
    {
        // ORDER|CMD_ID|TYPE|SYMBOL|LOT|PRICE
        if(cnt < 6)
        {
            SendResponse("ERROR|INVALID_ORDER_FORMAT");
            return;
        }
        
        string cmdId = parts[1];
        string type = parts[2];
        string symbol = parts[3];
        double lot = StringToDouble(parts[4]);
        double price = StringToDouble(parts[5]);
        
        // Idempotency check
        if(cmdId != "" && cmdId == g_lastCmdId)
        {
            Print("⚠️ Duplicate command: ", cmdId, " returning cached response");
            SendResponse(g_lastCmdResponse);
            return;
        }
        
        Print("📊 ORDER received:");
        Print("   CMD ID: ", cmdId);
        Print("   Type: ", type);
        Print("   Symbol: ", symbol);
        Print("   Lot: ", DoubleToStr(lot, 2));
        Print("   Price: ", DoubleToStr(price, 5));
        
        // Validate symbol
        if(symbol != InpSymbolLocal)
        {
            Print("❌ Symbol mismatch: ", symbol, " vs ", InpSymbolLocal);
            g_lastCmdId = cmdId;
            g_lastCmdResponse = "ERROR|SYMBOL_MISMATCH";
            SendResponse(g_lastCmdResponse);
            return;
        }
        
        // Validate order type
        int orderType = -1;
        if(type == "BUY")
            orderType = OP_BUY;
        else if(type == "SELL")
            orderType = OP_SELL;
        else
        {
            Print("❌ Invalid order type: ", type);
            g_lastCmdId = cmdId;
            g_lastCmdResponse = "ERROR|INVALID_ORDER_TYPE";
            SendResponse(g_lastCmdResponse);
            return;
        }
        
        // Validate price
        if(price <= 0)
        {
            Print("❌ Invalid price: ", DoubleToStr(price, 5));
            g_lastCmdId = cmdId;
            g_lastCmdResponse = "ERROR|INVALID_PRICE";
            SendResponse(g_lastCmdResponse);
            return;
        }
        
        // Validate lot size
        double minLot = MarketInfo(InpSymbolLocal, MODE_MINLOT);
        double maxLot = MarketInfo(InpSymbolLocal, MODE_MAXLOT);
        double stepLot = MarketInfo(InpSymbolLocal, MODE_LOTSTEP);
        
        if(lot < minLot || lot > maxLot)
        {
            Print("❌ Invalid lot: ", DoubleToStr(lot, 2));
            g_lastCmdId = cmdId;
            g_lastCmdResponse = "ERROR|INVALID_LOT";
            SendResponse(g_lastCmdResponse);
            return;
        }
        
        if(stepLot > 0)
        {
            double steps = (lot - minLot) / stepLot;
            double roundedSteps = MathRound(steps);
            if(MathAbs(steps - roundedSteps) > 0.0001)
            {
                Print("❌ Lot not multiple of step: ", DoubleToStr(stepLot, 2));
                g_lastCmdId = cmdId;
                g_lastCmdResponse = "ERROR|INVALID_LOT_STEP";
                SendResponse(g_lastCmdResponse);
                return;
            }
        }
        
        // Check if already has position
        if(g_hasPos)
        {
            Print("⚠️ Already has position! Ticket: ", g_ticket);
            g_lastCmdId = cmdId;
            g_lastCmdResponse = "ERROR|ALREADY_HAS_POSITION";
            SendResponse(g_lastCmdResponse);
            return;
        }
        
        // Price protection
        if(!PriceProtection(symbol, price, orderType))
        {
            g_lastCmdId = cmdId;
            g_lastCmdResponse = "ERROR|PRICE_CHANGED";
            SendResponse(g_lastCmdResponse);
            return;
        }
        
        // Execute order
        ExecuteOrder(orderType, symbol, lot, cmdId);
    }
    else if(parts[0] == "CLOSE")
    {
        // CLOSE|CMD_ID
        string cmdId = (cnt >= 2) ? parts[1] : "";
        
        if(cmdId != "" && cmdId == g_lastCmdId)
        {
            Print("⚠️ Duplicate CLOSE command: ", cmdId);
            SendResponse(g_lastCmdResponse);
            return;
        }
        
        Print("🔴 CLOSE received");
        bool ok = CloseAllOrders();
        
        g_lastCmdId = cmdId;
        if(ok)
            g_lastCmdResponse = "CLOSE_SUCCESS|ALL";
        else
            g_lastCmdResponse = "ERROR|CLOSE_FAILED";
        
        SendResponse(g_lastCmdResponse);
    }
    else if(parts[0] == "STATUS")
    {
        // STATUS|CMD_ID
        string cmdId = (cnt >= 2) ? parts[1] : "";
        
        SyncStateFromOrders();
        
        string response;
        if(g_hasPos)
            response = "STATUS|HAS_POSITION|" + IntegerToString(g_ticket);
        else
            response = "STATUS|NO_POSITION";
        
        g_lastCmdId = cmdId;
        g_lastCmdResponse = response;
        SendResponse(response);
    }
    else
    {
        Print("⚠️ Unknown command: ", cmd);
        SendResponse("ERROR|UNKNOWN_COMMAND");
    }
}

//+------------------------------------------------------------------+
//| EXECUTE ORDER                                                    |
//+------------------------------------------------------------------+
void ExecuteOrder(int type, string symbol, double lot, string cmdId)
{
    if(g_closing || g_shutdown)
    {
        g_lastCmdId = cmdId;
        g_lastCmdResponse = "ERROR|SYSTEM_CLOSING";
        SendResponse(g_lastCmdResponse);
        return;
    }
    
    RefreshRates();
    
    int digits = (int)MarketInfo(symbol, MODE_DIGITS);
    double execPrice = (type == OP_BUY) ? MarketInfo(symbol, MODE_ASK) : MarketInfo(symbol, MODE_BID);
    
    Print("🔨 Executing order:");
    Print("   Type: ", (type == OP_BUY) ? "BUY" : "SELL");
    Print("   Symbol: ", symbol);
    Print("   Lot: ", DoubleToStr(lot, 2));
    Print("   Price: ", DoubleToStr(execPrice, digits));
    
    int ticket = OrderSend(symbol, type, lot, execPrice, InpSlippage, 
                           0, 0, "Arbitrage B", InpMagic, 0, clrNONE);
    
    if(ticket > 0)
    {
        g_ticket = ticket;
        g_hasPos = true;
        g_profit = 0;
        Print("✅ Trade executed! Ticket: ", ticket);
        
        g_lastCmdId = cmdId;
        g_lastCmdResponse = "SUCCESS|" + IntegerToString(ticket);
        SendResponse(g_lastCmdResponse);
    }
    else
    {
        int err = GetLastError();
        Print("❌ Error executing trade: ", err);
        
        g_lastCmdId = cmdId;
        g_lastCmdResponse = "ERROR|" + IntegerToString(err);
        SendResponse(g_lastCmdResponse);
    }
}

//+------------------------------------------------------------------+
//| INITIALIZE ZMQ                                                   |
//+------------------------------------------------------------------+
bool InitZMQ()
{
    CleanupZMQ();
    
    g_ctx = new Context("arbitrage_slave");
    if(g_ctx == NULL)
    {
        Print("Failed to create ZMQ context");
        return false;
    }
    
    g_push = new Socket(g_ctx, ZMQ_PUSH);
    if(g_push == NULL)
    {
        Print("Failed to create PUSH socket");
        CleanupZMQ();
        return false;
    }
    
    string pushAddr = StringFormat("tcp://%s:%d", InpMasterIP, InpMasterPubPort);
    if(!g_push.connect(pushAddr))
    {
        Print("Cannot connect to PUSH: ", pushAddr);
        CleanupZMQ();
        return false;
    }
    Print("✅ PUSH connected to: ", pushAddr);
    
    g_rep = new Socket(g_ctx, ZMQ_REP);
    if(g_rep == NULL)
    {
        Print("Failed to create REP socket");
        CleanupZMQ();
        return false;
    }
    
    string repAddr = StringFormat("tcp://%s:%d", InpMasterIP, InpMasterRepPort);
    if(!g_rep.connect(repAddr))
    {
        Print("Cannot connect to REP: ", repAddr);
        CleanupZMQ();
        return false;
    }
    Print("✅ REP connected to: ", repAddr);
    
    g_socketReady = true;
    g_masterActive = false;
    g_lastHeartbeat = TimeCurrent();
    return true;
}

//+------------------------------------------------------------------+
//| CLEANUP ZMQ                                                      |
//+------------------------------------------------------------------+
void CleanupZMQ()
{
    if(g_push != NULL) { delete g_push; g_push = NULL; }
    if(g_rep != NULL) { delete g_rep; g_rep = NULL; }
    if(g_ctx != NULL) { delete g_ctx; g_ctx = NULL; }
    g_socketReady = false;
    g_masterActive = false;
}

//+------------------------------------------------------------------+
//| SAFE START                                                       |
//+------------------------------------------------------------------+
void SafeStart()
{
    if(g_running)
    {
        Print("Already running!");
        return;
    }
    
    Print("========================================");
    Print("  SAFE START - Slave");
    Print("========================================");
    
    if(!InitZMQ())
    {
        Print("ZMQ init failed!");
        return;
    }
    
    // Reset send state
    g_lastSentBid = 0.0;
    g_lastSentAsk = 0.0;
    g_lastSend = 0;
    g_lastHeartbeat = TimeCurrent();
    
    SyncStateFromOrders();
    
    g_running = true;
    g_shutdown = false;
    g_closing = false;
    g_masterActive = false;
    UpdateDisplay();
    Print("✅ Slave started!");
    Print("========================================");
    
    EventSetMillisecondTimer(TIMER_INTERVAL);
}

//+------------------------------------------------------------------+
//| SAFE STOP                                                        |
//+------------------------------------------------------------------+
void SafeStop()
{
    if(!g_running && !g_socketReady)
    {
        Print("Already stopped!");
        return;
    }
    
    Print("========================================");
    Print("  SAFE STOP - Slave");
    Print("========================================");
    
    EventKillTimer();
    
    g_shutdown = true;
    
    if(g_hasPos)
    {
        Print("Closing positions...");
        CloseAllOrders();
    }
    
    g_closing = true;
    CleanupZMQ();
    
    g_running = false;
    g_closing = false;
    g_shutdown = false;
    UpdateDisplay();
    Print("✅ Slave stopped!");
    Print("========================================");
}

//+------------------------------------------------------------------+
//| ONINIT                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("  ARBITRAGE SLAVE v6.3 FINAL");
    Print("========================================");
    Print("Symbol: ", InpSymbolLocal);
    Print("Server: ", InpMasterIP);
    Print("Magic: ", InpMagic);
    Print("========================================");
    
    // Validate symbol
    double testBid = MarketInfo(InpSymbolLocal, MODE_BID);
    if(testBid <= 0)
    {
        Print("ERROR: Symbol ", InpSymbolLocal, " not found or invalid!");
        Print("Please check symbol name and Market Watch");
        return INIT_FAILED;
    }
    Print("Symbol validation: Bid=", DoubleToStr(testBid, (int)MarketInfo(InpSymbolLocal, MODE_DIGITS)));
    Print("========================================");
    
    CreateUI();
    UpdateDisplay();
    SyncStateFromOrders();
    
    if(g_hasPos)
    {
        Print("⚠️ Existing position detected! Ticket: ", g_ticket);
    }
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| ONTIMER                                                          |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(g_shutdown)
    {
        if(TimeCurrent() - g_lastDisplay >= 1)
        {
            UpdateDisplay();
            g_lastDisplay = TimeCurrent();
        }
        return;
    }
    
    if(!g_running || g_closing) return;
    
    // Update local price
    g_bid = MarketInfo(InpSymbolLocal, MODE_BID);
    g_ask = MarketInfo(InpSymbolLocal, MODE_ASK);
    g_lastUpdate = TimeCurrent();
    
    if(g_bid <= 0 || g_ask <= 0) return;
    
    // Send price to Master with heartbeat
    if(g_push != NULL && g_socketReady)
    {
        bool priceChanged = (g_bid != g_lastSentBid || g_ask != g_lastSentAsk);
        bool heartbeatDue = (TimeCurrent() - g_lastSend >= 1);
        
        if(priceChanged || heartbeatDue)
        {
            int digits = (int)MarketInfo(InpSymbolLocal, MODE_DIGITS);
            string msg = InpSymbolLocal + "|" +
                         DoubleToStr(g_bid, digits) + "|" +
                         DoubleToStr(g_ask, digits) + "|" +
                         IntegerToString((int)g_lastUpdate);
            
            if(g_push.send(ZmqMsg(msg)))
            {
                g_lastSentBid = g_bid;
                g_lastSentAsk = g_ask;
                g_lastSend = TimeCurrent();
                g_lastHeartbeat = TimeCurrent();
                g_masterActive = true;
            }
            else
            {
                Print("⚠️ Failed to send price to Master");
            }
        }
    }
    
    // Receive commands from Master via REP
    if(g_rep != NULL && g_socketReady)
    {
        ZmqMsg cmd;
        if(g_rep.recv(cmd, false))
        {
            string data = cmd.getData();
            Print("📩 Received command: ", data);
            ProcessCommand(data);
        }
    }
    
    // Update profit
    if(g_hasPos && g_ticket > 0)
    {
        if(OrderSelect(g_ticket, SELECT_BY_TICKET, MODE_TRADES))
            g_profit = OrderProfit() + OrderSwap() + OrderCommission();
        else
        {
            g_hasPos = false;
            g_ticket = -1;
        }
    }
    
    if(TimeCurrent() - g_lastDisplay >= 1)
    {
        UpdateDisplay();
        g_lastDisplay = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| ONTICK                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
    // Timer handles all main logic
    // Sync state on tick to ensure positions are tracked
    if(g_running && !g_shutdown && !g_closing)
    {
        SyncStateFromOrders();
    }
}

//+------------------------------------------------------------------+
//| ONCHARTEVENT                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(sparam == BTN_START)
        {
            Print("START button clicked");
            SafeStart();
            ObjectSetInteger(0, BTN_START, OBJPROP_STATE, false);
            ChartRedraw(0);
        }
        else if(sparam == BTN_STOP)
        {
            Print("STOP button clicked");
            SafeStop();
            ObjectSetInteger(0, BTN_STOP, OBJPROP_STATE, false);
            ChartRedraw(0);
        }
    }
    
    if(id == CHARTEVENT_KEYDOWN)
    {
        if(sparam == "S" || sparam == "s") SafeStart();
        else if(sparam == "X" || sparam == "x") SafeStop();
    }
}

//+------------------------------------------------------------------+
//| ONDEINIT                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    
    if(g_running || g_socketReady) SafeStop();
    
    ObjectDelete(0, BTN_START);
    ObjectDelete(0, BTN_STOP);
    ObjectDelete(0, PREFIX + "Title");
    ObjectDelete(0, PREFIX + "Status");
    ObjectDelete(0, PREFIX + "Symbol");
    ObjectDelete(0, PREFIX + "Server");
    ObjectDelete(0, PREFIX + "Connected");
    ObjectDelete(0, PREFIX + "Position");
    ObjectDelete(0, PREFIX + "Ticket");
    ObjectDelete(0, PREFIX + "Profit");
    ObjectDelete(0, PREFIX + "Bid");
    ObjectDelete(0, PREFIX + "Ask");
    ChartRedraw(0);
    Print("Slave stopped.");
}
//+------------------------------------------------------------------+
```

---

## 📋 **دستورالعمل نصب و راه‌اندازی**

### **پیش‌نیازها**
1. MetaTrader 4 (نسخه ۶۰۰ یا بالاتر)
2. کتابخانه‌های `mql-zmq` و `mql4-lib`
3. فایل‌های DLL: `libzmq.dll` و `libsodium.dll`
4. پایتون ۳.۶ یا بالاتر (برای اسکریپت‌های نصب)

### **مراحل نصب**

#### **مرحله ۱: دانلود فایل‌های مورد نیاز**
```powershell
# دانلود از گیت‌هاب
mql4-lib: https://github.com/dingmaotu/mql4-lib
mql-zmq: https://github.com/dingmaotu/mql-zmq

# استخراج در پوشه
C:\Users\Avangard\Desktop\arbitrage\
```

#### **مرحله ۲: اجرای اسکریپت نصب**
```powershell
cd C:\Users\Avangard\Desktop\arbitrage
python install_arbitrage.py
```

#### **مرحله ۳: تنظیمات متاتریدر**
- **Tools → Options → Expert Advisors**
- ☑ Allow Automated Trading
- ☑ Allow DLL imports

#### **مرحله ۴: اجرای اکسپرت‌ها**

**Master (LiteFinance):**
1. چارت `XAUUSD_o` را باز کنید
2. `ArbitrageMaster.mq4` را روی چارت قرار دهید
3. پارامترها را به‌صورت پیش‌فرض نگه دارید
4. دکمه **START** را بزنید یا کلید **S** را فشار دهید

**Slave (OpoFinance):**
1. چارت `XAUUSD` را باز کنید
2. `ArbitrageSlave.mq4` را روی چارت قرار دهید
3. پارامترها را به‌صورت پیش‌فرض نگه دارید
4. دکمه **START** را بزنید یا کلید **S** را فشار دهید

---

## 📊 **جدول پارامترها**

### **Master (LiteFinance)**
| پارامتر | مقدار پیش‌فرض | توضیح |
|---------|---------------|-------|
| `InpSymbolLocal` | XAUUSD_o | نماد در LiteFinance |
| `InpSymbolRemote` | XAUUSD | نماد در OpoFinance |
| `InpMinSpread` | ۵۰ | حداقل اختلاف برای ورود (نقطه) |
| `InpLotSize` | ۰.۰۱ | حجم معامله |
| `InpSlippage` | ۵ | اسلیپیج مجاز |
| `InpMagic` | ۵۴۰۲ | شماره جادویی برای شناسایی معاملات |
| `InpCommandTimeout` | ۵ | تایم‌اوت دستورات (ثانیه) |
| `InpTakeProfit` | ۲.۰ | سود هدف (دلار) |
| `InpStopLoss` | ۱.۵ | حد ضرر (دلار) |
| `InpTrailingStart` | ۱.۰ | شروع تریلینگ (دلار) |
| `InpTrailingStep` | ۰.۵ | گام تریلینگ (دلار) |
| `InpMaxTimeMinutes` | ۵ | حداکثر زمان معامله (دقیقه) |
| `InpRiskFreeThreshold` | ۰.۵ | آستانه ریسک‌فری (دلار) |

### **Slave (OpoFinance)**
| پارامتر | مقدار پیش‌فرض | توضیح |
|---------|---------------|-------|
| `InpMasterIP` | ۱۲۷.۰.۰.۱ | آدرس IP سرور |
| `InpMasterPubPort` | ۵۵۵۵ | پورت دریافت قیمت |
| `InpMasterRepPort` | ۵۵۵۶ | پورت دریافت دستورات |
| `InpSymbolLocal` | XAUUSD | نماد در OpoFinance |
| `InpLotSize` | ۰.۰۱ | حجم معامله |
| `InpSlippage` | ۵ | اسلیپیج مجاز |
| `InpMagic` | ۵۴۰۲ | شماره جادویی |

---

## 🔧 **عیب‌یابی**

### **خطاهای رایج و راه‌حل‌ها**

| خطا | دلیل | راه‌حل |
|-----|------|-------|
| `ERROR sending order!` | ارتباط ZMQ قطع است | فایروال را بررسی کنید، پورت‌ها را باز کنید |
| `No response from slave` | Slave متصل نیست | Slave را ری‌استارت کنید |
| `Invalid price for XAUUSD` | نماد درست تنظیم نشده | نام نماد را در `InpSymbolLocal` بررسی کنید |
| `OrderSend failed` | حجم معامله نامعتبر | `InpLotSize` را با حداقل حجم بروکر تطابق دهید |
| `REQ timeout` | پاسخ دریافت نشد | `InpCommandTimeout` را افزایش دهید |
| `Symbol not found` | نماد در Market Watch نیست | نماد را به Market Watch اضافه کنید |

---

## 📈 **نظارت بر عملکرد**

### **وضعیت‌های نمایش داده شده**
| وضعیت | رنگ | توضیح |
|-------|-----|-------|
| `INIT` | خاکستری | در حال راه‌اندازی |
| `READY` | سفید | آماده برای شروع |
| `CONNECTING` | زرد | در حال اتصال به Slave |
| `RUNNING` | سبز | در حال اجرا و فعال |
| `CLOSING` | نارنجی | در حال بستن معاملات |
| `SHUTDOWN` | قرمز | متوقف شده |

### **معیارهای موفقیت**
- **Status:** RUNNING (سبز)
- **Connected:** YES (سبز)
- **Diff:** > InpMinSpread (سبز)
- **Position:** BUY/SELL (زرد)
- **Risk-Free:** ACTIVE (سبز)

---

## 📝 **نتیجه‌گیری**

سیستم آربیتراژ v6.3 یک راه‌حل کامل و حرفه‌ای برای اجرای معاملات آربیتراژ بین دو بروکر است. با ویژگی‌های:

- ✅ **ارتباط پایدار** از طریق ZMQ با مکانیزم Heartbeat
- ✅ **Idempotency** با استفاده از Command ID
- ✅ **Reconciliation** با دستور STATUS
- ✅ **مدیریت ریسک کامل** (SL/TP، Trailing Stop، Risk-Free)
- ✅ **UI کامل** با دکمه‌های Start/Stop و نمایش وضعیت
- ✅ **Safe Start/Stop** با مدیریت clean shutdown
- ✅ **Emergency Alerts** برای شرایط بحرانی

این سیستم برای اجرا در حساب‌های دمو و واقعی (پس از تست کافی) آماده است. 🚀



--------------------------------
گزارش خیلی خوب و منظم شروع شده؛ ساختار معماری، مسیر پیام‌ها و نقش Master/Slave کاملاً قابل‌فهم است. برای اینکه این «گزارش نهایی v6.3» واقعاً کامل و قابل ارائه/آرشیو شود، پیشنهاد می‌کنم چند بخش حیاتی دیگر به آن اضافه شود: **منطق تصمیم‌گیری، مدیریت ریسک، سناریوهای خطا، محدودیت‌ها، چک‌لیست تست و توصیه‌های اجرای لایو**.

در ادامه یک نسخه تکمیلی پیشنهادی برای ادامه همین گزارش می‌دهم که می‌توانی مستقیم به انتهای سند اضافه کنی.

---

## 🧠 منطق تصمیم‌گیری Master

Master مسئول تشخیص فرصت آربیتراژ و تصمیم‌گیری برای ورود یا خروج از معامله است. این تصمیم بر اساس اختلاف قیمت بین قیمت محلی LiteFinance و قیمت دریافتی از OpoFinance انجام می‌شود.

### فرمول اختلاف قیمت

برای نماد طلا:

\[
Diff = \frac{Price_{Local} - Price_{Remote}}{Point}
\]

اگر اختلاف از حداقل اسپرد تعریف‌شده بیشتر شود، Master فرصت را معتبر تشخیص می‌دهد.

### شرایط ورود

Master فقط زمانی وارد معامله می‌شود که همه شرایط زیر برقرار باشند:

| شرط | توضیح |
|---|---|
| سیستم Running باشد | دکمه START فعال شده باشد |
| اتصال ZMQ فعال باشد | socketها آماده باشند |
| قیمت Slave تازه باشد | heartbeat معتبر باشد |
| پوزیشن باز وجود نداشته باشد | جلوگیری از ورود چندباره |
| اختلاف قیمت از `InpMinSpread` بیشتر باشد | فرصت واقعی آربیتراژ |
| Master و Slave هر دو قابل معامله باشند | جلوگیری از معامله ناقص |

### جهت معامله

اگر قیمت Master نسبت به Slave بالاتر باشد:

```text
Master: SELL
Slave : BUY
```

اگر قیمت Master نسبت به Slave پایین‌تر باشد:

```text
Master: BUY
Slave : SELL
```

هدف این است که دو پوزیشن مخالف روی دو بروکر باز شوند تا اختلاف قیمت شکار شود.

---

## 🛡️ مدیریت ریسک

سیستم v6.3 دارای چند لایه مدیریت ریسک است که روی Master کنترل می‌شود.

### پارامترهای اصلی

| پارامتر | مقدار نمونه | توضیح |
|---|---:|---|
| `InpTakeProfit` | `2.0` | بستن کل سیستم در سود مشخص |
| `InpStopLoss` | `1.5` | بستن کل سیستم در زیان مشخص |
| `InpTrailingStart` | `1.0` | شروع trailing بعد از رسیدن به سود مشخص |
| `InpTrailingStep` | `0.5` | فاصله trailing از بیشترین سود |
| `InpMaxTimeMinutes` | `5` | حداکثر زمان نگهداری پوزیشن |
| `InpRiskFreeThreshold` | `0.5` | فعال‌سازی حالت ریسک‌فری |

### حالت Risk-Free

وقتی سود تجمیعی دو سمت معامله از حد مشخص‌شده عبور کند، سیستم وارد حالت Risk-Free می‌شود.

در این حالت، هدف اصلی سیستم این است که اجازه ندهد معامله سودده دوباره وارد زیان قابل‌توجه شود.

```text
اگر Profit >= RiskFreeThreshold:
    Risk-Free = ACTIVE
```

### Trailing Profit

بعد از عبور سود از `InpTrailingStart`، بالاترین سود ثبت می‌شود و اگر سود از قله خود به اندازه `InpTrailingStep` کاهش یابد، سیستم تمام پوزیشن‌ها را می‌بندد.

نمونه:

```text
TrailingStart = 1.0
TrailingStep  = 0.5

MaxProfit = 2.2
CurrentProfit = 1.7

چون 2.2 - 1.7 = 0.5
=> بستن پوزیشن‌ها
```

---

## 🔐 Idempotency و Command ID

یکی از مهم‌ترین بهبودهای نسخه v6.3 اضافه شدن `CMD_ID` به همه دستورات حساس است.

### هدف Command ID

در سیستم‌های توزیع‌شده، ممکن است این اتفاق رخ دهد:

1. Master دستور `ORDER` را ارسال می‌کند.
2. Slave سفارش را واقعاً اجرا می‌کند.
3. پاسخ `SUCCESS|TICKET` به Master نمی‌رسد.
4. Master تصور می‌کند دستور fail شده است.
5. Master همان دستور را دوباره می‌فرستد.

بدون `CMD_ID`، Slave ممکن است معامله دوم باز کند.  
اما در v6.3، Slave آخرین command id و پاسخ آن را ذخیره می‌کند.

```text
g_lastCmdId
g_lastCmdResponse
```

اگر همان دستور دوباره دریافت شود:

```text
اگر cmdId == g_lastCmdId:
    همان پاسخ قبلی ارسال می‌شود
    سفارش جدید باز نمی‌شود
```

این مکانیزم سیستم را در برابر duplicate execution مقاوم می‌کند.

---

## 🔎 Reconciliation با STATUS

برای هماهنگ‌سازی وضعیت واقعی دو ترمینال، دستور `STATUS` اضافه شده است.

### کاربرد STATUS

Master در شرایط زیر از Slave وضعیت می‌گیرد:

| شرایط | هدف |
|---|---|
| timeout در پاسخ ORDER | بررسی اینکه آیا سفارش واقعاً اجرا شده یا نه |
| timeout در CLOSE | بررسی اینکه آیا پوزیشن هنوز باز است یا نه |
| اختلاف state داخلی | همگام‌سازی مجدد |
| recovery بعد از reset socket | بازسازی وضعیت سیستم |

### پاسخ‌های ممکن

```text
STATUS|HAS_POSITION|TICKET
STATUS|NO_POSITION
```

این ویژگی باعث می‌شود Master فقط بر اساس حدس تصمیم نگیرد و وضعیت واقعی Slave را بررسی کند.

---

## ⚠️ سناریوهای خطا و واکنش سیستم

### 1. اجرای Master موفق، اجرای Slave ناموفق

```text
Master order opened
Slave order failed
```

واکنش سیستم:

1. Master خطا را تشخیص می‌دهد.
2. از Slave وضعیت می‌گیرد.
3. اگر Slave پوزیشن ندارد، پوزیشن Master بسته می‌شود.
4. اگر بستن Master fail شود، هشدار اضطراری صادر می‌شود.

### 2. اجرای Slave موفق، پاسخ به Master گم می‌شود

```text
Slave executed order
Reply lost
```

واکنش سیستم:

1. Master timeout دریافت می‌کند.
2. با `STATUS` وضعیت Slave را بررسی می‌کند.
3. اگر پوزیشن وجود داشته باشد، state را reconcile می‌کند.
4. از باز کردن سفارش تکراری جلوگیری می‌شود.

### 3. دستور CLOSE ارسال می‌شود اما پاسخ نمی‌رسد

```text
CLOSE sent
Reply timeout
```

واکنش سیستم:

1. Master دستور `STATUS` می‌فرستد.
2. اگر `STATUS|NO_POSITION` برگردد، بستن موفق فرض می‌شود.
3. اگر `STATUS|HAS_POSITION` برگردد، mismatch گزارش می‌شود.
4. در صورت نیاز alert فوری ارسال می‌شود.

### 4. قطع price stream

اگر Master بیش از چند ثانیه heartbeat یا قیمت جدید دریافت نکند:

```text
g_masterActive = false
```

در این حالت Master فرصت جدید باز نمی‌کند تا از تصمیم‌گیری روی قیمت stale جلوگیری شود.

---

## 🧪 چک‌لیست تست قبل از اجرای واقعی

### تست‌های ارتباطی

| تست | نتیجه مورد انتظار |
|---|---|
| روشن کردن Slave قبل از Master | Master قیمت دریافت کند |
| روشن کردن Master قبل از Slave | بعد از شروع Slave اتصال برقرار شود |
| قطع کردن Slave هنگام اجرا | Master inactive شود |
| وصل مجدد Slave | price stream و STATUS برگردد |
| timeout در REQ/REP | socket reset شود |

### تست‌های معاملاتی

| تست | نتیجه مورد انتظار |
|---|---|
| باز کردن یک فرصت مصنوعی | دو پوزیشن مخالف باز شوند |
| رد شدن سفارش Slave | پوزیشن Master بسته شود |
| رد شدن سفارش Master | دستوری به Slave ارسال نشود یا state پاک بماند |
| بسته شدن دستی پوزیشن Slave | STATUS وضعیت جدید را تشخیص دهد |
| بسته شدن دستی پوزیشن Master | SyncStateFromOrders وضعیت را اصلاح کند |

### تست‌های ریسک

| تست | نتیجه مورد انتظار |
|---|---|
| رسیدن به Take Profit | هر دو سمت بسته شوند |
| رسیدن به Stop Loss | هر دو سمت بسته شوند |
| فعال شدن Risk-Free | وضعیت UI تغییر کند |
| فعال شدن Trailing | با برگشت سود، پوزیشن‌ها بسته شوند |
| رسیدن به Max Time | خروج زمانی انجام شود |

---

## 🚨 محدودیت‌های شناخته‌شده

با وجود اینکه v6.3 از نظر نرم‌افزاری بسیار بهتر از نسخه‌های قبلی است، چند محدودیت ذاتی همچنان وجود دارد.

### 1. اجرای کاملاً همزمان تضمین‌شده نیست

در MT4 و بروکرهای retail، اجرای همزمان واقعی وجود ندارد. همیشه ممکن است یکی از سفارش‌ها چند میلی‌ثانیه زودتر یا دیرتر اجرا شود.

### 2. ZMQ آنلاین بودن واقعی طرف مقابل را تضمین نمی‌کند

ارسال موفق روی socket لزوماً به معنی دریافت موفق توسط طرف مقابل نیست. به همین دلیل heartbeat و STATUS اضافه شده‌اند، اما همچنان تضمین صددرصدی وجود ندارد.

### 3. اختلاف قیمت ممکن است قبل از اجرا از بین برود

حتی اگر فرصت در لحظه تشخیص معتبر باشد، ممکن است هنگام ارسال سفارش، بازار حرکت کند یا بروکر requote بدهد.

### 4. بروکر ممکن است آربیتراژ را محدود کند

برخی بروکرها نسبت به latency arbitrage حساس هستند و ممکن است:

```text
Execution delay
Slippage expansion
Requote
Order rejection
Account review
Profit cancellation
```

اعمال کنند.

### 5. کیفیت VPS حیاتی است

سیستم کم‌تاخیر به شدت به کیفیت شبکه، CPU، RAM، پینگ و پایداری VPS وابسته است.

---

## ✅ جمع‌بندی نسخه v6.3

نسخه v6.3 نسبت به نسخه‌های قبلی از چند جهت پیشرفت اساسی دارد:

| حوزه | وضعیت v6.3 |
|---|---|
| ارتباط قیمت | پایدارتر با heartbeat |
| ارسال سفارش | امن‌تر با command id |
| جلوگیری از duplicate order | پیاده‌سازی شده |
| reconciliation | پیاده‌سازی شده با STATUS |
| مدیریت close | دارای retry و بررسی وضعیت |
| مدیریت ریسک | TP/SL/Trailing/Risk-Free/Time Exit |
| UI | دارای وضعیت سیستم، پوزیشن، سود و اختلاف قیمت |
| پایداری عملیاتی | مناسب برای forward test کنترل‌شده |

نتیجه نهایی:

```text
Arbitrage System v6.3 = Operationally Testable
```

یعنی سیستم از مرحله prototype عبور کرده و برای تست عملیاتی روی حساب دمو یا حساب real با سرمایه بسیار محدود آماده است؛ اما هنوز نیازمند مانیتورینگ، لاگ‌گیری دقیق و تست فشار است.

---

## 🔧 پیشنهادهای نسخه بعدی v6.4

برای نسخه بعدی، چند ارتقای مهم پیشنهاد می‌شود:

1. **Non-blocking REQ/REP کامل**
   حذف `Sleep()` از مسیرهای حساس و تبدیل همه commandها به state machine غیرمسدودکننده.

2. **Persistent command journal**
   ذخیره command id، ticket، response و وضعیت معامله در فایل یا GlobalVariable برای recovery بعد از crash.

3. **Telegram/Push notification**
   ارسال هشدار فوری برای mismatch، close failure، order failure و disconnected state.

4. **Latency measurement**
   افزودن timestamp به پیام‌ها و محاسبه latency واقعی بین دو ترمینال.

5. **Spread/slippage analytics**
   ذخیره اختلاف قیمت، زمان اجرا، slippage و نتیجه هر معامله برای تحلیل آماری.

6. **Emergency flatten mode**
   دکمه یا فرمان اضطراری برای بستن همه معاملات در هر دو ترمینال بدون توجه به state داخلی.

7. **Broker execution profiling**
   اندازه‌گیری میانگین execution time، reject rate و slippage برای هر بروکر.

---

اگر بخواهم خیلی فشرده بگویم: گزارش شما پایه خوبی دارد، اما با اضافه شدن بخش‌های بالا تبدیل می‌شود به یک **Technical Final Report** کامل، نه فقط توضیح معماری.