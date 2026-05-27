# memory_see.py
# 直接執行這個檔案就能看 pet_memory.db 裡的所有記憶
# 用法：python memory_see.py

import sqlite3
from pathlib import Path
from datetime import datetime, timedelta

DB_PATH = Path(__file__).parent / "pet_memory.db"

RETENTION_DAYS = {
    "days_7": 7,
    "days_3": 3,
}


def normalize_importance(importance: str) -> str:
    """相容舊版 important / normal。"""
    if importance == "important":
        return "permanent"
    if importance == "normal":
        return "days_7"
    return importance


def view():
    # 檢查資料庫檔案是否存在
    if not DB_PATH.exists():
        print(f"找不到資料庫：{DB_PATH}")
        print("請先啟動 main_api.py 讓它自動建立 pet_memory.db")
        return

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute("""
        SELECT key, importance, value, updated_at
        FROM memories
        ORDER BY
            CASE importance
                WHEN 'permanent' THEN 0
                WHEN 'important' THEN 0
                WHEN 'days_7' THEN 1
                WHEN 'normal' THEN 1
                WHEN 'days_3' THEN 2
                ELSE 3
            END,
            updated_at DESC
    """).fetchall()
    conn.close()

    if not rows:
        print("目前沒有任何記憶。")
        return

    now = datetime.now()

    personality = [r for r in rows if r["key"].startswith("personality:")]
    permanent   = [r for r in rows if normalize_importance(r["importance"]) == "permanent"
                   and not r["key"].startswith("personality:")]
    days_7 = [r for r in rows if normalize_importance(r["importance"]) == "days_7"]
    days_3 = [r for r in rows if normalize_importance(r["importance"]) == "days_3"]

    print("=" * 60)
    print(f"  pet_memory.db　共 {len(rows)} 筆記憶")
    print("=" * 60)

    if personality:
        print(f"\n個性記憶（{len(personality)} 筆，永久保留）")
        print("-" * 60)
        for r in personality:
            display_key = r["key"][len("personality:"):]
            print(f"  {display_key:<20} {r['value']}")
            print(f"  {'':20} 更新於 {r['updated_at']}")

    if permanent:
        print(f"\n永久記憶（{len(permanent)} 筆）")
        print("-" * 60)
        for r in permanent:
            print(f"  {r['key']:<20} {r['value']}")
            print(f"  {'':20} 更新於 {r['updated_at']}")

    for importance, title, group in [
        ("days_7", "7 天記憶", days_7),
        ("days_3", "3 天記憶", days_3),
    ]:
        if not group:
            continue
        retention_days = RETENTION_DAYS[importance]
        print(f"\n{title}（{len(group)} 筆，{retention_days} 天未更新自動刪除）")
        print("-" * 60)
        for r in group:
            updated   = datetime.strptime(r["updated_at"], "%Y-%m-%d %H:%M:%S")
            expire    = updated + timedelta(days=retention_days)
            days_left = (expire - now).days + 1
            if days_left <= 1:
                tag = "明天到期"
            elif days_left <= 3:
                tag = f"剩 {days_left} 天"
            else:
                tag = f"剩 {days_left} 天"
            print(f"  {r['key']:<20} {r['value']}")
            print(f"  {'':20} 更新於 {r['updated_at']}　{tag}")

    print("\n" + "=" * 60)


if __name__ == "__main__":
    view()