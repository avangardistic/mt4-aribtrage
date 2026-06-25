import os
import shutil
from pathlib import Path

# =============================================
# مسیرهای اصلی
# =============================================
BASE_DIR = Path(r"C:\Users\Avangard\Desktop\arbitrage")
MQL4_LIB_SRC = BASE_DIR / "mql4-lib-master"
MQL_ZMQ_SRC = BASE_DIR / "mql-zmq-master"
OUTPUT_DIR = BASE_DIR / "MQL4"

OUTPUT_INCLUDE = OUTPUT_DIR / "Include"
OUTPUT_LIBRARIES = OUTPUT_DIR / "Libraries"

# =============================================
# پوشه‌های مورد نیاز از mql4-lib
# =============================================
REQUIRED_FOLDERS = [
    "Lang",        # کلاسهای پایه (ExpertAdvisor, Script, و غیره)
    "Trade",       # کلاسهای معاملاتی (Order, OrderPool, و غیره)
    "Collection",  # ساختارهای داده (HashMap, Vector, و غیره)
    "Utils",       # ابزارهای کمکی (File, Time, و غیره)
    "Format",      # سریالسازی (Json, Resp, و غیره)
    "History",     # دادههای تاریخی
    "Charts",      # ابزارهای چارت
]

# =============================================
# توابع کمکی
# =============================================
def copy_folder(src_path, dest_path):
    """کپی کردن یک پوشه از مسیر مبدا به مقصد"""
    if not src_path.exists():
        print(f"❌ پوشه مبدا یافت نشد: {src_path}")
        return False
    
    if dest_path.exists():
        shutil.rmtree(dest_path)
        print(f"🗑️  پوشه قدیمی حذف شد: {dest_path}")
    
    try:
        shutil.copytree(src_path, dest_path)
        print(f"✅ کپی شد: {src_path} -> {dest_path}")
        return True
    except Exception as e:
        print(f"❌ خطا در کپی {src_path.name}: {e}")
        return False

def copy_file(src_path, dest_path, file_name):
    """کپی کردن یک فایل از مسیر مبدا به مقصد"""
    src_file = src_path / file_name
    dest_file = dest_path / file_name
    
    if not src_file.exists():
        print(f"❌ فایل مبدا یافت نشد: {src_file}")
        return False
    
    dest_path.mkdir(parents=True, exist_ok=True)
    
    try:
        shutil.copy2(src_file, dest_file)
        print(f"✅ کپی شد: {src_file} -> {dest_file}")
        return True
    except Exception as e:
        print(f"❌ خطا در کپی {file_name}: {e}")
        return False

# =============================================
# تابع اصلی
# =============================================
def organize_files():
    print("=" * 70)
    print("🚀 شروع سازماندهی فایلهای کتابخانه‌های MQL")
    print("=" * 70)
    
    # بررسی وجود پوشه‌های مبدا
    if not MQL4_LIB_SRC.exists():
        print(f"❌ پوشه mql4-lib-master یافت نشد: {MQL4_LIB_SRC}")
        return
    if not MQL_ZMQ_SRC.exists():
        print(f"❌ پوشه mql-zmq-master یافت نشد: {MQL_ZMQ_SRC}")
        return
    
    # ایجاد پوشه‌های خروجی
    OUTPUT_INCLUDE.mkdir(parents=True, exist_ok=True)
    OUTPUT_LIBRARIES.mkdir(parents=True, exist_ok=True)
    print(f"📁 پوشه‌های خروجی ایجاد شدند:")
    print(f"   {OUTPUT_INCLUDE}")
    print(f"   {OUTPUT_LIBRARIES}")
    
    # ===== کپی پوشه‌های مورد نیاز از mql4-lib =====
    print("\n" + "-" * 70)
    print("📦 کپی فایلهای mql4-lib...")
    print("-" * 70)
    
    # ایجاد پوشه Mql در مقصد
    DEST_MQL = OUTPUT_INCLUDE / "Mql"
    DEST_MQL.mkdir(parents=True, exist_ok=True)
    
    for folder in REQUIRED_FOLDERS:
        src_folder = MQL4_LIB_SRC / folder
        dest_folder = DEST_MQL / folder
        
        if src_folder.exists():
            copy_folder(src_folder, dest_folder)
        else:
            print(f"⚠️  پوشه {folder} در mql4-lib یافت نشد، رد میشود...")
    
    # ===== کپی فایلهای ZMQ =====
    print("\n" + "-" * 70)
    print("📦 کپی فایلهای mql-zmq...")
    print("-" * 70)
    
    # کپی پوشه Zmq
    zmq_src = MQL_ZMQ_SRC / "Include" / "Zmq"
    if zmq_src.exists():
        dest_zmq = OUTPUT_INCLUDE / "Zmq"
        copy_folder(zmq_src, dest_zmq)
    else:
        print(f"❌ پوشه Zmq یافت نشد: {zmq_src}")
    
    # ===== کپی فایلهای DLL =====
    print("\n📦 کپی فایلهای DLL...")
    copy_file(MQL_ZMQ_SRC / "Library" / "MT4", OUTPUT_LIBRARIES, "libzmq.dll")
    copy_file(MQL_ZMQ_SRC / "Library" / "MT4", OUTPUT_LIBRARIES, "libsodium.dll")
    
    # ===== نمایش خلاصه =====
    print("\n" + "-" * 70)
    print("📋 خلاصه نهایی")
    print("-" * 70)
    
    # نمایش ساختار پوشه ایجاد شده
    print("\n📁 ساختار پوشه ایجاد شده:")
    for root, dirs, files in os.walk(OUTPUT_DIR):
        level = root.replace(str(OUTPUT_DIR), "").count(os.sep)
        indent = " " * 2 * level
        folder_name = os.path.basename(root)
        if level == 0:
            print(f"{indent}📂 {folder_name}/")
        else:
            print(f"{indent}📂 {folder_name}/")
        
        # نمایش فایلهای هر پوشه (تا ۳ فایل)
        if level < 3 and files:
            sub_indent = " " * 2 * (level + 1)
            for file in files[:3]:
                print(f"{sub_indent}📄 {file}")
            if len(files) > 3:
                print(f"{sub_indent}... و {len(files) - 3} فایل دیگر")
    
    total_files = sum(len(files) for _, _, files in os.walk(OUTPUT_DIR))
    
    print("\n" + "=" * 70)
    print(f"✅ عملیات با موفقیت انجام شد!")
    print(f"📊 تعداد کل فایلهای کپی شده: {total_files}")
    print(f"📂 مسیر خروجی: {OUTPUT_DIR}")
    print("=" * 70)
    
    # ===== نمایش فایلهای اسکریپت مورد نیاز =====
    print("\n📝 گام بعدی: سه فایل اسکریپت زیر را در پوشه‌های مربوطه قرار دهید:")
    print("   📄 ArbitrageMaster.mq4  -> MQL4/Experts/")
    print("   📄 ArbitrageSlave.mq4   -> MQL4/Experts/")
    print("   📄 TestZmqConnection.mq4 -> MQL4/Scripts/")
    print("\n💡 سپس متاتریدر را ریستارت کرده و اکسپرت‌ها را روی چارت قرار دهید.")

# =============================================
# اجرای اسکریپت
# =============================================
if __name__ == "__main__":
    try:
        organize_files()
    except Exception as e:
        print(f"\n❌ خطای غیرمنتظره: {e}")
        import traceback
        traceback.print_exc()
    
    input("\nبرای خروج کلید Enter را بزنید...")