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

enum ENUM_APP_STATE
{
    STATE_STOPPED,
    STATE_STARTING,
    STATE_RUNNING,
    STATE_STOPPING,
    STATE_CLOSING,
    STATE_RECONCILING,
    STATE_ERROR,
    STATE_STOP_FAILED,
    STATE_MANUAL_CHECK_REQUIRED
};

enum ENUM_STOP_PHASE
{
    STOP_PHASE_IDLE,
    STOP_PHASE_SEND_CLOSE,
    STOP_PHASE_WAIT_CLOSE,
    STOP_PHASE_SEND_STATUS,
    STOP_PHASE_WAIT_STATUS,
    STOP_PHASE_CLOSE_MASTER,
    STOP_PHASE_CLEANUP,
    STOP_PHASE_DONE,
    STOP_PHASE_FAILED,
    STOP_PHASE_MANUAL_CHECK
};

ENUM_APP_STATE  g_appState = STATE_STOPPED;
ENUM_STOP_PHASE g_stopPhase = STOP_PHASE_IDLE;
bool            g_stopRequested = false;
bool            g_slaveStopConfirmed = false;
bool            g_slaveStatusKnown = false;
bool            g_slaveHasPosition = false;
string          g_stopCmdId = "";
string          g_stopStatusCmdId = "";
datetime        g_stopPhaseTime = 0;
int             g_stopCloseAttempts = 0;
int             g_stopStatusAttempts = 0;
int             g_masterCloseAttempts = 0;
int             g_lastHeartbeatMs = 0;
uint            g_lastHeartbeatTick = 0;
uint            g_lastRenderTick = 0;

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

    ObjectCreate(0, PREFIX + "Heartbeat", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, PREFIX + "Heartbeat", OBJPROP_XDISTANCE, x0);
    ObjectSetInteger(0, PREFIX + "Heartbeat", OBJPROP_YDISTANCE, y0 + step * 12);
    ObjectSetInteger(0, PREFIX + "Heartbeat", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, PREFIX + "Heartbeat", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, PREFIX + "Heartbeat", OBJPROP_COLOR, clrRed);
    ObjectSetString(0, PREFIX + "Heartbeat", OBJPROP_TEXT, "Heartbeat: ● OFFLINE • ---");
    ObjectSetString(0, PREFIX + "Heartbeat", OBJPROP_FONT, "Arial");
    
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| UPDATE DISPLAY                                                   |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
    string status;
    color clr;
    
    switch(g_appState)
    {
        case STATE_STARTING:
            status = "STARTING";
            clr = clrYellow;
            break;
        case STATE_RUNNING:
            status = (g_masterActive ? "RUNNING" : "RUNNING - WAITING HEARTBEAT");
            clr = (g_masterActive ? clrLimeGreen : clrOrange);
            break;
        case STATE_STOPPING:
            status = "STOPPING...";
            clr = clrOrange;
            break;
        case STATE_CLOSING:
            status = "CLOSING";
            clr = clrOrange;
            break;
        case STATE_RECONCILING:
            status = "RECONCILING";
            clr = clrYellow;
            break;
        case STATE_ERROR:
            status = "ERROR";
            clr = clrRed;
            break;
        case STATE_STOP_FAILED:
            status = "STOP_FAILED";
            clr = clrRed;
            break;
        case STATE_MANUAL_CHECK_REQUIRED:
            status = "MANUAL_CHECK_REQUIRED";
            clr = clrRed;
            break;
        default:
            status = "STOPPED";
            clr = clrGray;
            break;
    }
    
    ObjectSetString(0, PREFIX + "Status", OBJPROP_TEXT, "Status: " + status);
    ObjectSetInteger(0, PREFIX + "Status", OBJPROP_COLOR, clr);
    
    if(g_hasPos)
    {
        string type = (g_orderType == OP_BUY) ? "BUY" : "SELL";
        ObjectSetString(0, PREFIX + "Profit", OBJPROP_TEXT, "Profit: $" + DoubleToStr(g_profit, 2));
        ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_COLOR, g_profit >= 0 ? clrLimeGreen : clrRed);
        ObjectSetString(0, PREFIX + "Position", OBJPROP_TEXT, "Position: " + type);
        ObjectSetInteger(0, PREFIX + "Position", OBJPROP_COLOR, clrYellow);
        ObjectSetString(0, PREFIX + "Ticket", OBJPROP_TEXT, "Ticket: " + IntegerToString(g_ticket));
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
    }
    else
    {
        ObjectSetString(0, PREFIX + "Profit", OBJPROP_TEXT, "Profit: $0.00");
        ObjectSetInteger(0, PREFIX + "Profit", OBJPROP_COLOR, clrGray);
        ObjectSetString(0, PREFIX + "Position", OBJPROP_TEXT, "Position: NONE");
        ObjectSetInteger(0, PREFIX + "Position", OBJPROP_COLOR, clrGray);
        ObjectSetString(0, PREFIX + "Ticket", OBJPROP_TEXT, "Ticket: -");
        ObjectSetString(0, PREFIX + "Time", OBJPROP_TEXT, "Time: 0 min");
        ObjectSetString(0, PREFIX + "RiskFree", OBJPROP_TEXT, "Risk-Free: OFF");
        ObjectSetInteger(0, PREFIX + "RiskFree", OBJPROP_COLOR, clrGray);
        ObjectSetString(0, PREFIX + "Trailing", OBJPROP_TEXT, "Trailing: $0.00");
        ObjectSetInteger(0, PREFIX + "Trailing", OBJPROP_COLOR, clrGray);
    }
    
    ObjectSetString(0, PREFIX + "Diff", OBJPROP_TEXT, "Diff: " + DoubleToStr(g_diff, 1) + " pts");
    ObjectSetInteger(0, PREFIX + "Diff", OBJPROP_COLOR, g_diff >= InpMinSpread ? clrLimeGreen : clrGray);
    
    string hbText = "Heartbeat: ● OFFLINE • ---";
    color hbColor = clrRed;
    if(g_socketReady && g_lastHeartbeatTick > 0 && g_appState != STATE_STOPPED && g_appState != STATE_STOP_FAILED && g_appState != STATE_MANUAL_CHECK_REQUIRED)
    {
        int ageMs = (int)(GetTickCount() - g_lastHeartbeatTick);
        string ageText = "";
        if(ageMs <= 1000)
        {
            hbText = "Heartbeat: ● LIVE • " + IntegerToString(ageMs) + " ms ago";
            hbColor = clrLimeGreen;
        }
        else if(ageMs <= 3000)
        {
            ageText = DoubleToStr((double)ageMs / 1000.0, 1) + "s ago";
            hbText = "Heartbeat: ● STALE • " + ageText;
            hbColor = clrOrange;
        }
        else
        {
            ageText = DoubleToStr((double)ageMs / 1000.0, 1) + "s ago";
            hbText = "Heartbeat: ● OFFLINE • " + ageText;
            hbColor = clrRed;
        }
    }
    ObjectSetString(0, PREFIX + "Heartbeat", OBJPROP_TEXT, hbText);
    ObjectSetInteger(0, PREFIX + "Heartbeat", OBJPROP_COLOR, hbColor);
    
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
    g_lastHeartbeat = 0;
    g_lastHeartbeatTick = 0;
    g_lastPriceReceived = 0;
    g_slaveBid = 0.0;
    g_slaveAsk = 0.0;
}

void ResetReqSocket()
{
    if(g_req != NULL)
    {
        delete g_req;
        g_req = NULL;
    }
    
    if(g_ctx == NULL || !g_socketReady) return;
    
    g_req = new Socket(g_ctx, ZMQ_REQ);
    if(g_req != NULL)
    {
        string reqAddr = StringFormat("tcp://*:%d", InpSlavePort);
        if(g_req.bind(reqAddr))
            Print("REQ socket reset");
        else
            Print("❌ Failed to reset REQ socket");
    }
    
    g_reqState = REQ_READY;
}

bool SendCommandAsync(string command)
{
    if(g_req == NULL || !g_socketReady || g_reqState != REQ_READY)
        return false;
    
    g_pendingCommand = command;
    g_reqState = REQ_WAITING_REPLY;
    g_lastReqTime = TimeCurrent();
    
    Print("📤 Sending async: ", command);
    if(!g_req.send(ZmqMsg(command)))
    {
        Print("❌ Async send failed: ", command);
        g_reqState = REQ_READY;
        return false;
    }
    
    return true;
}

bool PollCommandReply(string &response)
{
    response = "";
    if(g_req == NULL || g_reqState != REQ_WAITING_REPLY)
        return false;
    
    ZmqMsg reply;
    if(g_req.recv(reply, false))
    {
        response = reply.getData();
        Print("📨 Async response: ", response);
        g_reqState = REQ_READY;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| SAFE START                                                       |
//+------------------------------------------------------------------+
void SafeStart()
{
    if(g_running || g_stopRequested)
    {
        Print("Already running or stopping!");
        return;
    }
    
    Print("========================================");
    Print("  SAFE START");
    Print("========================================");
    
    g_appState = STATE_STARTING;
    UpdateDisplay();
    
    if(!InitZMQ())
    {
        Print("ZMQ init failed!");
        g_appState = STATE_ERROR;
        UpdateDisplay();
        return;
    }
    
    SyncStateFromOrders();
    
    g_running = true;
    g_shutdown = false;
    g_closing = false;
    g_masterActive = false;
    g_stopRequested = false;
    g_stopPhase = STOP_PHASE_IDLE;
    g_appState = STATE_RUNNING;
    g_lastHeartbeat = 0;
    g_lastHeartbeatTick = 0;
    UpdateDisplay();
    Print("✅ Started!");
    Print("========================================");
    
    EventSetMillisecondTimer(TIMER_INTERVAL);
}

void RequestStop()
{
    if(g_stopRequested || g_appState == STATE_STOPPED)
    {
        Print("Stop already requested or stopped.");
        return;
    }
    
    Print("STOP requested - async state machine started");
    g_stopRequested = true;
    g_running = false;
    g_closing = true;
    g_shutdown = false;
    g_masterActive = false;
    g_lastHeartbeat = 0;
    g_lastPriceReceived = 0;
    g_lastHeartbeatTick = 0;
    g_slaveBid = 0.0;
    g_slaveAsk = 0.0;
    g_appState = STATE_STOPPING;
    g_stopPhase = STOP_PHASE_SEND_CLOSE;
    g_stopPhaseTime = TimeCurrent();
    g_slaveStopConfirmed = false;
    g_slaveStatusKnown = false;
    g_slaveHasPosition = false;
    g_stopCloseAttempts = 0;
    g_stopStatusAttempts = 0;
    g_masterCloseAttempts = 0;
    g_stopCmdId = GenerateCmdId();
    g_stopStatusCmdId = "";
    
    EventSetMillisecondTimer(TIMER_INTERVAL);
    UpdateDisplay();
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

bool CloseTicketOneAttempt(int ticket)
{
    if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
        return true;
    
    if(OrderType() != OP_BUY && OrderType() != OP_SELL)
    {
        ResetLastError();
        if(OrderDelete(ticket))
            return true;
        Print("Delete failed: ", GetLastError());
        return false;
    }
    
    RefreshRates();
    double closePrice = (OrderType() == OP_BUY) ? MarketInfo(OrderSymbol(), MODE_BID)
                                                 : MarketInfo(OrderSymbol(), MODE_ASK);
    if(closePrice <= 0)
        return false;
    
    ResetLastError();
    if(OrderClose(ticket, OrderLots(), closePrice, InpSlippage, clrNONE))
    {
        Print("✅ Closed: ", ticket);
        return true;
    }
    
    Print("Close attempt failed. Ticket=", ticket, " Error=", GetLastError());
    return false;
}

void FinishStop(ENUM_APP_STATE finalState)
{
    EventKillTimer();
    CleanupZMQ();
    g_running = false;
    g_closing = false;
    g_shutdown = false;
    g_stopRequested = false;
    g_stopPhase = STOP_PHASE_IDLE;
    g_appState = finalState;
    
    SyncStateFromOrders();
    if(!g_hasPos)
    {
        g_ticket = -1;
        g_profit = 0.0;
        g_timeMin = 0;
        g_highestProfit = 0.0;
        g_trailingLevel = 0.0;
        g_riskFree = false;
    }
    
    UpdateDisplay();
}

void ProcessStopStateMachine()
{
    if(!g_stopRequested) return;
    
    string response = "";
    
    if(g_reqState == REQ_WAITING_REPLY && TimeCurrent() - g_lastReqTime > InpCommandTimeout)
    {
        Print("⏰ Stop REQ timeout. Resetting socket...");
        ResetReqSocket();
        if(g_stopPhase == STOP_PHASE_WAIT_CLOSE)
            g_stopPhase = STOP_PHASE_SEND_STATUS;
        else if(g_stopPhase == STOP_PHASE_WAIT_STATUS)
            g_stopPhase = STOP_PHASE_CLOSE_MASTER;
        g_stopPhaseTime = TimeCurrent();
    }
    
    switch(g_stopPhase)
    {
        case STOP_PHASE_SEND_CLOSE:
            g_appState = STATE_STOPPING;
            if(g_req == NULL || !g_socketReady)
            {
                Print("⚠️ No Slave socket during stop; local close and manual verification required.");
                g_slaveStatusKnown = false;
                g_stopPhase = STOP_PHASE_CLOSE_MASTER;
                break;
            }
            
            if(g_reqState != REQ_READY)
                break;
            
            if(g_stopCloseAttempts >= 2)
            {
                g_stopPhase = STOP_PHASE_SEND_STATUS;
                break;
            }
            
            g_stopCloseAttempts++;
            g_stopCmdId = GenerateCmdId();
            if(SendCommandAsync("CLOSE|" + g_stopCmdId))
            {
                g_stopPhase = STOP_PHASE_WAIT_CLOSE;
                g_stopPhaseTime = TimeCurrent();
            }
            else
            {
                ResetReqSocket();
                g_stopPhase = STOP_PHASE_SEND_STATUS;
            }
            break;
        
        case STOP_PHASE_WAIT_CLOSE:
            g_appState = STATE_STOPPING;
            if(PollCommandReply(response))
            {
                if(StringFind(response, "CLOSE_SUCCESS") >= 0 || StringFind(response, "SUCCESS") >= 0)
                {
                    g_slaveStopConfirmed = true;
                    g_slaveStatusKnown = true;
                    g_slaveHasPosition = false;
                    g_stopPhase = STOP_PHASE_CLOSE_MASTER;
                }
                else
                {
                    Print("⚠️ CLOSE response requires reconciliation: ", response);
                    g_stopPhase = STOP_PHASE_SEND_STATUS;
                }
                g_stopPhaseTime = TimeCurrent();
            }
            break;
        
        case STOP_PHASE_SEND_STATUS:
            g_appState = STATE_RECONCILING;
            if(g_req == NULL || !g_socketReady)
            {
                g_stopPhase = STOP_PHASE_CLOSE_MASTER;
                break;
            }
            
            if(g_reqState != REQ_READY)
                break;
            
            if(g_stopStatusAttempts >= 2)
            {
                Print("⚠️ STATUS reconciliation failed after retries.");
                g_stopPhase = STOP_PHASE_CLOSE_MASTER;
                break;
            }
            
            g_stopStatusAttempts++;
            g_stopStatusCmdId = GenerateCmdId();
            if(SendCommandAsync("STATUS|" + g_stopStatusCmdId))
            {
                g_stopPhase = STOP_PHASE_WAIT_STATUS;
                g_stopPhaseTime = TimeCurrent();
            }
            else
            {
                ResetReqSocket();
                g_stopPhase = STOP_PHASE_CLOSE_MASTER;
            }
            break;
        
        case STOP_PHASE_WAIT_STATUS:
            g_appState = STATE_RECONCILING;
            if(PollCommandReply(response))
            {
                if(StringFind(response, "STATUS|NO_POSITION") >= 0)
                {
                    g_slaveStatusKnown = true;
                    g_slaveHasPosition = false;
                    g_slaveStopConfirmed = true;
                    g_stopPhase = STOP_PHASE_CLOSE_MASTER;
                }
                else if(StringFind(response, "STATUS|HAS_POSITION") >= 0)
                {
                    g_slaveStatusKnown = true;
                    g_slaveHasPosition = true;
                    if(g_stopCloseAttempts < 2)
                        g_stopPhase = STOP_PHASE_SEND_CLOSE;
                    else
                        g_stopPhase = STOP_PHASE_CLOSE_MASTER;
                }
                else
                {
                    g_stopPhase = STOP_PHASE_CLOSE_MASTER;
                }
                g_stopPhaseTime = TimeCurrent();
            }
            break;
        
        case STOP_PHASE_CLOSE_MASTER:
            g_appState = STATE_CLOSING;
            SyncStateFromOrders();
            if(!g_hasPos || g_ticket <= 0)
            {
                g_stopPhase = STOP_PHASE_CLEANUP;
                break;
            }
            
            if(g_masterCloseAttempts >= 5)
            {
                Print("❌ Master close failed after bounded retries.");
                g_stopPhase = STOP_PHASE_MANUAL_CHECK;
                break;
            }
            
            g_masterCloseAttempts++;
            if(CloseTicketOneAttempt(g_ticket))
            {
                SyncStateFromOrders();
                g_stopPhase = STOP_PHASE_CLEANUP;
            }
            break;
        
        case STOP_PHASE_CLEANUP:
            if(g_slaveHasPosition || !g_slaveStatusKnown)
            {
                Print("⚠️ Stop completed locally, but Slave reconciliation is uncertain.");
                FinishStop(STATE_MANUAL_CHECK_REQUIRED);
            }
            else
            {
                FinishStop(STATE_STOPPED);
            }
            break;
        
        case STOP_PHASE_MANUAL_CHECK:
            FinishStop(STATE_MANUAL_CHECK_REQUIRED);
            break;
        
        case STOP_PHASE_FAILED:
            FinishStop(STATE_STOP_FAILED);
            break;
        
        default:
            g_stopPhase = STOP_PHASE_CLEANUP;
            break;
    }
    
    UpdateDisplay();
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
    if(!g_hasPos || g_ticket <= 0 || g_closing || g_stopRequested) return;
    
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
    if(g_stopRequested || !g_running || g_appState != STATE_RUNNING) return;
    
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
    if(g_closing || g_hasPos || g_shutdown || g_stopRequested || !g_running || g_appState != STATE_RUNNING) return;
    
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
    if(g_stopRequested)
    {
        ProcessStopStateMachine();
        return;
    }
    
    if(!g_running || g_closing || g_shutdown)
    {
        UpdateDisplay();
        return;
    }
    
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
                g_lastHeartbeatTick = GetTickCount();
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
    
    if(GetTickCount() - g_lastRenderTick >= 250)
    {
        UpdateDisplay();
        g_lastRenderTick = GetTickCount();
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
            RequestStop();
            ObjectSetInteger(0, BTN_STOP, OBJPROP_STATE, false);
            ChartRedraw(0);
        }
    }
    
    if(id == CHARTEVENT_KEYDOWN)
    {
        if(sparam == "S" || sparam == "s") SafeStart();
        else if(sparam == "X" || sparam == "x") RequestStop();
    }
}

//+------------------------------------------------------------------+
//| ONDEINIT                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    
    CleanupZMQ();
    
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
    ObjectDelete(0, PREFIX + "Heartbeat");
    ChartRedraw(0);
    Print("Master stopped.");
}
//+------------------------------------------------------------------+
