#property link          "https://www.earnforex.com/metatrader-indicators/moving-average-crossover-alert/"
#property version       "1.06"

#property copyright     "EarnForex.com - 2020-2024"
#property description   "The RSI indicator with alerts."
#property description   ""
#property description   "WARNING: Use this software at your own risk."
#property description   "The creator of this indicator cannot be held responsible for any damage or loss."
#property description   ""
#property description   "Find more on www.EarnForex.com"
#property icon          "\\Files\\EF-Icon-64x64px.ico"

#property indicator_separate_window
#property indicator_buffers 1
#property indicator_plots 1
#property indicator_color1 clrBlue
#property indicator_type1 DRAW_LINE
#property indicator_width1  1
#property indicator_label1  "RSI"
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_level1 30
#property indicator_level2 70

#include <MQLTA ErrorHandling.mqh>
#include <MQLTA Utils.mqh>

enum ENUM_TRADE_SIGNAL
{
    SIGNAL_BUY = 1,     // Buy
    SIGNAL_SELL = -1,   // Sell
    SIGNAL_NEUTRAL = 0, // Neutral
    SIGNAL_HLINE = 2    // Horizontal Line Cross
};

enum ENUM_CANDLE_TO_CHECK
{
    CURRENT_CANDLE, // Current Candle
    CLOSED_CANDLE   // Previous Candle
};

enum ENUM_ALERT_SIGNAL
{
    RSI_BREAK_OUT, // RSI Breaks out of Limits
    RSI_COMES_IN,  // RSI Returns to the Limits
    RSI_COMES_IN_AFTER_REACHING_OUT // RSI Returns to the Limits After Reaching Target
};

input string Comment1 = "========================";        // MQLTA RSI With Alert
input string IndicatorName = "MQLTA-RSIWA";                // Indicator Short Name
input string Comment2 = "========================";        // Indicator Parameters
input int RSIPeriod = 14;                                  // RSI Period
input int RSIHighLimit = 70;                               // RSI Overbought Limit
input int RSILowLimit = 30;                                // RSI Oversold Limit
input ENUM_APPLIED_PRICE RSIAppliedPrice = PRICE_CLOSE;    // RSI Applied Price
input int BarsToScan = 500;                                // Number Of Candles To Analyze (0 = All)
input ENUM_CANDLE_TO_CHECK CandleToCheck = CURRENT_CANDLE; // Candle To Use For Analysis
input ENUM_ALERT_SIGNAL AlertSignal = RSI_COMES_IN;        // Alert Signal When
input int RSITopTarget = 99;                               // RSI Top Target
input int RSILowTarget = 1;                                // RSI Low Target
input string Comment_3 = "====================";           // Notification Options
input bool EnableNotify = false;                           // Enable Notifications Feature
input bool SendAlert = true;                               // Send Alert Notification
input bool SendApp = false;                                // Send Notification to Mobile
input bool SendEmail = false;                              // Send Notification via Email
input int WaitTimeNotify = 5;                              // Wait Time Between Notifications (Seconds)
input string Comment_4 = "====================";           // Drawing Options
input bool EnableDrawArrows = true;                        // Draw Signal Arrows
input int ArrowBuy = 241;                                  // Buy Arrow Code
input int ArrowSell = 242;                                 // Sell Arrow Code
input int ArrowSize = 3;                                   // Arrow Size (1-5)
input color ArrowBuyColor = clrGreen;                      // Buy Arrow Color
input color ArrowSellColor = clrRed;                       // Sell Arrow Color

double BufferMain[];
int BufferMainHandle;
datetime LastNotificationTime;
ENUM_TRADE_SIGNAL LastNotificationDirection;
double LineLevel = 0; // For horizontal line cross signals.
int Shift = 0;

int OnInit()
{
    IndicatorSetString(INDICATOR_SHORTNAME, IndicatorName + " - RSI (" + string(RSIPeriod) + ") - ");

    OnInitInitialization();
    if (!OnInitPreChecksPass())
    {
        return INIT_FAILED;
    }

    InitialiseHandles();
    InitialiseBuffers();

    return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    bool IsNewCandle = CheckIfNewCandle();

    int counted_bars = 0;
    if (prev_calculated > 0) counted_bars = prev_calculated - 1;

    if (counted_bars < 0) return -1;
    if (counted_bars > 0) counted_bars--;
    int limit = rates_total - counted_bars;
    if ((BarsToScan > 0) && (limit > BarsToScan))
    {
        limit = BarsToScan;
        if (rates_total < BarsToScan + RSIPeriod) limit = rates_total - RSIPeriod;
    }
    if (limit > rates_total - RSIPeriod) limit = rates_total - RSIPeriod;
    
    if (CopyBuffer(BufferMainHandle, 0, 0, limit, BufferMain) <= 0)
    {
        Print("Failed to create the indicator! Error: ", GetLastErrorText(GetLastError()), " - ", GetLastError());
        return 0;
    }

    if ((IsNewCandle) || (prev_calculated == 0))
    {
        if (EnableDrawArrows) DrawArrows(limit);
        CleanUpOldArrows();
    }

    if (EnableDrawArrows) DrawArrow(0);

    if (EnableNotify) NotifyHit();

    return rates_total;
}

void OnDeinit(const int reason)
{
    CleanChart();
}

void OnInitInitialization()
{
    LastNotificationTime = TimeCurrent();
    Shift = CandleToCheck;
}

bool OnInitPreChecksPass()
{
    if ((RSIPeriod <= 0) || (RSIHighLimit > 100) || (RSIHighLimit < 0) || (RSILowLimit > 100) || (RSILowLimit < 0) || (RSILowLimit > RSIHighLimit))
    {
        Print("Wrong input parameters.");
        return false;
    }
    return true;
}

void CleanChart()
{
    ObjectsDeleteAll(ChartID(), IndicatorName);
}

void InitialiseHandles()
{
    BufferMainHandle = iRSI(Symbol(), PERIOD_CURRENT, RSIPeriod, RSIAppliedPrice);
}

void InitialiseBuffers()
{
    IndicatorSetInteger(INDICATOR_DIGITS, 2);
    ArraySetAsSeries(BufferMain, true);
    SetIndexBuffer(0, BufferMain, INDICATOR_DATA);
    IndicatorSetInteger(INDICATOR_LEVELS, 2);
    IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, (double)RSILowLimit);
    IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, (double)RSIHighLimit);
    PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, RSIPeriod);
    if (AlertSignal == RSI_COMES_IN_AFTER_REACHING_OUT) // If required mark the target levels.
    {
        IndicatorSetInteger(INDICATOR_LEVELS, 4);
        IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, (double)RSILowLimit);
        IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, (double)RSIHighLimit);
        IndicatorSetDouble(INDICATOR_LEVELVALUE, 2, (double)RSITopTarget);
        IndicatorSetDouble(INDICATOR_LEVELVALUE, 3, (double)RSILowTarget);
    }
}

datetime NewCandleTime = TimeCurrent();
bool CheckIfNewCandle()
{
    if (NewCandleTime == iTime(Symbol(), 0, 0)) return false;
    else
    {
        NewCandleTime = iTime(Symbol(), 0, 0);
        return true;
    }
}

// Check if it is a trade signal: 0 = Neutral, 1 = Buy, -1 = Sell.
ENUM_TRADE_SIGNAL IsSignal(int i)
{
    int j = i + Shift;
    if (AlertSignal == RSI_BREAK_OUT)
    {
        if ((BufferMain[j + 1] < RSIHighLimit) && (BufferMain[j] > RSIHighLimit)) return SIGNAL_BUY;
        else if ((BufferMain[j + 1] > RSILowLimit) && (BufferMain[j] < RSILowLimit)) return SIGNAL_SELL;
    }
    else if (AlertSignal == RSI_COMES_IN)
    {
        if ((BufferMain[j + 1] < RSILowLimit) && (BufferMain[j] > RSILowLimit)) return SIGNAL_BUY;
        else if ((BufferMain[j + 1] > RSIHighLimit) && (BufferMain[j] < RSIHighLimit)) return SIGNAL_SELL;
    }
    else if (AlertSignal == RSI_COMES_IN_AFTER_REACHING_OUT)
    {
        int _BarsToScan = BarsToScan;
        if ((_BarsToScan == 0) || (_BarsToScan > iBars(Symbol(), Period()))) _BarsToScan = iBars(Symbol(), Period());
        if ((BufferMain[j + 1] < RSILowLimit) && (BufferMain[j] > RSILowLimit))
        {
            // Check whether the target has been reached before this return to the range.
            for (int k = j + 1; k < _BarsToScan; k++)
            {
                if (BufferMain[k] > RSILowLimit) break; // Didn't reach the target during this breakout.
                if (BufferMain[k] <= RSILowTarget) return SIGNAL_BUY;
            }
        }
        if ((BufferMain[j + 1] > RSIHighLimit) && (BufferMain[j] < RSIHighLimit))
        {
            // Check whether the target has been reached before this return to the range.
            for (int k = j + 1; k < _BarsToScan; k++)
            {
                if (BufferMain[k] < RSIHighLimit) break; // Didn't reach the target during this breakout.
                if (BufferMain[k] >= RSITopTarget) return SIGNAL_SELL;
            }
        }
    }

    // Find horizontal lines in the indicator's subwindow, check for crosses.
    int Window = WindowFind(IndicatorName + " - RSI (" + string(RSIPeriod) + ") - ");
    int hlines_total = ObjectsTotal(ChartID(), Window, OBJ_HLINE);
    for (int k = 0; k < hlines_total; k++)
    {
        string object_name = ObjectName(ChartID(), k, Window, OBJ_HLINE);
        LineLevel = ObjectGetDouble(ChartID(), object_name, OBJPROP_PRICE, 0);
        if (((BufferMain[j + 1] < LineLevel) && (BufferMain[j] > LineLevel)) ||
            ((BufferMain[j + 1] > LineLevel) && (BufferMain[j] < LineLevel))) return SIGNAL_HLINE;
    }

    return SIGNAL_NEUTRAL;
}

void NotifyHit()
{
    if (!EnableNotify) return;
    if ((!SendAlert) && (!SendApp) && (!SendEmail)) return;
    if (CandleToCheck == CLOSED_CANDLE)
    {
        if (iTime(Symbol(), Period(), 0) <= LastNotificationTime) return;
    }
    else // Current candle.
    {
        if (TimeCurrent() - LastNotificationTime < WaitTimeNotify) return; // Notifications are coming too fast.
    }
    ENUM_TRADE_SIGNAL Signal = IsSignal(0);
    if (Signal == SIGNAL_NEUTRAL)
    {
        LastNotificationDirection = Signal;
        return;
    }
    if (Signal == LastNotificationDirection) return;
    string EmailSubject = IndicatorName + " " + Symbol() + " Notification";
    string EmailBody = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + "\r\n" + IndicatorName + " Notification for " + Symbol() + " @ " + EnumToString((ENUM_TIMEFRAMES)Period()) + "\r\n";
    string AlertText = "";
    string AppText = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + " - " + IndicatorName + " - " + Symbol() + " @ " + EnumToString((ENUM_TIMEFRAMES)Period()) + " - ";
    string Text = "";

    Text += EnumToString(Signal);
    if (Signal == SIGNAL_HLINE) Text += " - Line Level = " + DoubleToString(LineLevel, 2);

    EmailBody += Text;
    AlertText += Text;
    AppText += Text;
    if (SendAlert) Alert(AlertText);
    if (SendEmail)
    {
        if (!SendMail(EmailSubject, EmailBody)) Print("Error sending email " + IntegerToString(GetLastError()));
    }
    if (SendApp)
    {
        if (!SendNotification(AppText)) Print("Error sending notification " + IntegerToString(GetLastError()));
    }
    LastNotificationTime = TimeCurrent();
    LastNotificationDirection = Signal;
}

void DrawArrows(int limit)
{
    for (int i = limit - 1; i >= 1; i--)
    {
        DrawArrow(i);
    }
}

void DrawArrow(int i)
{
    RemoveArrowCurr();
    ENUM_TRADE_SIGNAL Signal = IsSignal(i);
    if ((Signal == SIGNAL_NEUTRAL) || (Signal == SIGNAL_HLINE)) return;
    datetime ArrowDate = iTime(Symbol(), 0, i);
    string ArrowName = IndicatorName + "-ARWS-" + IntegerToString(ArrowDate);
    double ArrowPrice = 0;
    ENUM_OBJECT ArrowType = OBJ_ARROW;
    color ArrowColor = 0;
    int ArrowAnchor = 0;
    string ArrowDesc = "";
    if (Signal == SIGNAL_BUY)
    {
        ArrowPrice = iLow(Symbol(), Period(), i);
        ArrowType = (ENUM_OBJECT)ArrowBuy;
        ArrowColor = ArrowBuyColor;
        ArrowAnchor = ANCHOR_TOP;
        ArrowDesc = "BUY";
    }
    if (Signal == SIGNAL_SELL)
    {
        ArrowPrice = iHigh(Symbol(), Period(), i);
        ArrowType = (ENUM_OBJECT)ArrowSell;
        ArrowColor = ArrowSellColor;
        ArrowAnchor = ANCHOR_BOTTOM;
        ArrowDesc = "SELL";
    }
    ObjectCreate(0, ArrowName, OBJ_ARROW, 0, ArrowDate, ArrowPrice);
    ObjectSetInteger(0, ArrowName, OBJPROP_COLOR, ArrowColor);
    ObjectSetInteger(0, ArrowName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, ArrowName, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, ArrowName, OBJPROP_ANCHOR, ArrowAnchor);
    ObjectSetInteger(0, ArrowName, OBJPROP_ARROWCODE, ArrowType);
    ObjectSetInteger(0, ArrowName, OBJPROP_WIDTH, ArrowSize);
    ObjectSetInteger(0, ArrowName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, ArrowName, OBJPROP_BGCOLOR, ArrowColor);
    ObjectSetString(0, ArrowName, OBJPROP_TEXT, ArrowDesc);

}

void RemoveArrowCurr()
{
    datetime ArrowDate = iTime(Symbol(), 0, 0);
    string ArrowName = IndicatorName + "-ARWS-" + IntegerToString(ArrowDate);
    ObjectDelete(0, ArrowName);
}

// Delete all arrows that are older than BarsToScan bars.
void CleanUpOldArrows()
{
    int total = ObjectsTotal(ChartID(), 0, OBJ_ARROW);
    for (int i = total - 1; i >= 0; i--)
    {
        string ArrowName = ObjectName(ChartID(), i, 0, OBJ_ARROW);
        datetime time = (datetime)ObjectGetInteger(ChartID(), ArrowName, OBJPROP_TIME);
        int bar = iBarShift(Symbol(), Period(), time);
        if ((BarsToScan > 0) && (bar >= BarsToScan)) ObjectDelete(ChartID(), ArrowName);
    }
}
//+------------------------------------------------------------------+