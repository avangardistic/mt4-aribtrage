import os
from pathlib import Path

BASE_DIR = Path(r"C:\Users\Avangard\Desktop\arbitrage")
MQL4_LIB_SRC = BASE_DIR / "mql4-lib-master"

print("=" * 60)
print("🔍 بررسی ساختار پوشه mql4-lib-master")
print("=" * 60)

if not MQL4_LIB_SRC.exists():
    print(f"❌ پوشه وجود ندارد: {MQL4_LIB_SRC}")
else:
    print(f"✅ پوشه پیدا شد: {MQL4_LIB_SRC}")
    print("\n📂 محتویات پوشه mql4-lib-master:")
    
    for item in MQL4_LIB_SRC.iterdir():
        if item.is_dir():
            print(f"  📁 {item.name}/")
            # نمایش زیرپوشهها
            for sub in item.iterdir():
                if sub.is_dir():
                    print(f"    📁 {sub.name}/")
                else:
                    print(f"    📄 {sub.name}")
        else:
            print(f"  📄 {item.name}")

print("\n" + "=" * 60)
print("🔍 بررسی پوشه Include (اگر وجود دارد)")
print("=" * 60)

include_path = MQL4_LIB_SRC / "Include"
if include_path.exists():
    print(f"✅ پوشه Include پیدا شد: {include_path}")
    for item in include_path.iterdir():
        if item.is_dir():
            print(f"  📁 {item.name}/")
            # نمایش یک سطح پایینتر
            for sub in item.iterdir():
                if sub.is_dir():
                    print(f"    📁 {sub.name}/")
        else:
            print(f"  📄 {item.name}")
else:
    print(f"❌ پوشه Include وجود ندارد: {include_path}")
    print("\n💡 بررسی پوشه اصلی برای یافتن فایلهای MQL...")
    
    # جستجوی فایلهای .mqh در کل پوشه
    mqh_files = list(MQL4_LIB_SRC.glob("**/*.mqh"))
    if mqh_files:
        print(f"\n✅ تعداد فایلهای .mqh پیدا شده: {len(mqh_files)}")
        print("\n📂 مسیرهای پیدا شده:")
        for f in mqh_files[:5]:  # نمایش ۵ فایل اول
            print(f"  {f.relative_to(MQL4_LIB_SRC)}")
        if len(mqh_files) > 5:
            print(f"  ... و {len(mqh_files) - 5} فایل دیگر")
    else:
        print("❌ هیچ فایل .mqh پیدا نشد!")

input("\nبرای خروج کلید Enter را بزنید...")