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

# مسیرهای خروجی
OUTPUT_INCLUDE = OUTPUT_DIR / "Include"
OUTPUT_LIBRARIES = OUTPUT_DIR / "Libraries"

# =============================================
# توابع کمکی
# =============================================
def copy_folder(src_path, dest_path, folder_name):
    """کپی کردن یک پوشه از مسیر مبدا به مقصد"""
    src_folder = src_path / folder_name
    dest_folder = dest_path / folder_name
    
    if not src_folder.exists():
        print(f"❌ پوشه مبدا یافت نشد: {src_folder}")
        return False
    
    # حذف پوشه مقصد اگر وجود داشته باشد
    if dest_folder.exists():
        shutil.rmtree(dest_folder)
        print(f"🗑️  پوشه قدیمی حذف شد: {dest_folder}")
    
    # کپی پوشه
    try:
        shutil.copytree(src_folder, dest_folder)
        print(f"✅ کپی شد: {src_folder} -> {dest_folder}")
        return True
    except Exception as e:
        print(f"❌ خطا در کپی {folder_name}: {e}")
        return False

def copy_file(src_path, dest_path, file_name):
    """کپی کردن یک فایل از مسیر مبدا به مقصد"""
    src_file = src_path / file_name
    dest_file = dest_path / file_name
    
    if not src_file.exists():
        print(f"❌ فایل مبدا یافت نشد: {src_file}")
        return False
    
    # ایجاد پوشه مقصد اگر وجود ندارد
    dest_path.mkdir(parents=True, exist_ok=True)
    
    # کپی فایل
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
    print("=" * 60)
    print("🚀 شروع سازماندهی فایلهای کتابخانه‌های MQL")
    print("=" * 60)
    
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
    print(f"📁 پوشه‌های خروجی ایجاد شدند:\n   {OUTPUT_INCLUDE}\n   {OUTPUT_LIBRARIES}")
    
    print("\n" + "-" * 60)
    print("📦 کپی فایلهای mql4-lib...")
    print("-" * 60)
    
    # کپی پوشه Mql از mql4-lib
    copy_folder(MQL4_LIB_SRC / "Include", OUTPUT_INCLUDE, "Mql")
    
    print("\n" + "-" * 60)
    print("📦 کپی فایلهای mql-zmq...")
    print("-" * 60)
    
    # کپی پوشه Zmq از mql-zmq
    copy_folder(MQL_ZMQ_SRC / "Include", OUTPUT_INCLUDE, "Zmq")
    
    # کپی فایلهای DLL
    print("\n📦 کپی فایلهای DLL...")
    copy_file(MQL_ZMQ_SRC / "Library" / "MT4", OUTPUT_LIBRARIES, "libzmq.dll")
    copy_file(MQL_ZMQ_SRC / "Library" / "MT4", OUTPUT_LIBRARIES, "libsodium.dll")
    
    print("\n" + "-" * 60)
    print("📋 خلاصه نهایی")
    print("-" * 60)
    
    # نمایش ساختار پوشه ایجاد شده
    print("\n📁 ساختار پوشه ایجاد شده:")
    for root, dirs, files in os.walk(OUTPUT_DIR):
        level = root.replace(str(OUTPUT_DIR), "").count(os.sep)
        indent = " " * 2 * level
        print(f"{indent}📂 {os.path.basename(root)}/")
        sub_indent = " " * 2 * (level + 1)
        for file in files:
            print(f"{sub_indent}📄 {file}")
    
    # تعداد فایلهای کپی شده
    total_files = 0
    for root, dirs, files in os.walk(OUTPUT_DIR):
        total_files += len(files)
    
    print("\n" + "=" * 60)
    print(f"✅ عملیات با موفقیت انجام شد!")
    print(f"📊 تعداد کل فایلهای کپی شده: {total_files}")
    print(f"📂 مسیر خروجی: {OUTPUT_DIR}")
    print("=" * 60)
    
    # نمایش فایلهای اسکریپت مورد نیاز
    print("\n📝 نکته: سه فایل اسکریپت زیر را نیز در پوشه‌های مربوطه قرار دهید:")
    print("   📄 ArbitrageMaster.mq4  -> MQL4/Experts/")
    print("   📄 ArbitrageSlave.mq4   -> MQL4/Experts/")
    print("   📄 TestZmqConnection.mq4 -> MQL4/Scripts/")

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
    
    # مکث برای مشاهده خروجی
    input("\nبرای خروج کلید Enter را بزنید...")