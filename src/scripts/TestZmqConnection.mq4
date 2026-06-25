//+------------------------------------------------------------------+
//|                                          TestZmqConnection.mq4   |
//|                                          تست اتصال ZMQ           |
//+------------------------------------------------------------------+
#property copyright "Arbitrage System"
#property link      ""
#property version   "1.00"
#property strict

#include <Zmq/Zmq.mqh>

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("=== شروع تست اتصال ZMQ ===");
    
    // بررسی وجود DLLها
    if(!CheckDLLs())
    {
        Print("❌ خطا: DLLهای ZMQ یافت نشدند!");
        Print("لطفاً فایل‌های libzmq.dll و libsodium.dll را در پوشه Libraries کپی کنید.");
        return;
    }
    
    // تست ایجاد کانتکست
    Print("✅ تست ایجاد کانتکست...");
    Context context("test_context");
    Print("✅ کانتکست با موفقیت ایجاد شد.");
    
    // تست ایجاد سوکت
    Print("✅ تست ایجاد سوکت...");
    Socket socket(context, ZMQ_REQ);
    Print("✅ سوکت با موفقیت ایجاد شد.");
    
    Print("=== تست با موفقیت انجام شد! ===");
    Print("نکته: اگر خطایی ظاهر نشد، همه چیز به درستی نصب شده است.");
}

//+------------------------------------------------------------------+
//| بررسی وجود فایل‌های DLL                                          |
//+------------------------------------------------------------------+
bool CheckDLLs()
{
    bool found = false;
    
    string dlls[] = {"libzmq.dll", "libsodium.dll"};
    
    for(int i = 0; i < ArraySize(dlls); i++)
    {
        string path = "\\Libraries\\" + dlls[i];
        if(FileIsExist(path))
        {
            Print("✅ " + dlls[i] + " یافت شد.");
            found = true;
        }
        else
        {
            Print("❌ " + dlls[i] + " یافت نشد!");
            found = false;
        }
    }
    
    return found;
}
//+------------------------------------------------------------------+