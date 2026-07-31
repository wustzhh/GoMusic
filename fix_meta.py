"""批量补全旧歌的 metadata.json（时长+作者）"""
import os
import json
import vlc
import time

DOWNLOADS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "downloads")

instance = vlc.Instance("--no-xlib")
player = instance.media_player_new()

count = 0
for f in os.listdir(DOWNLOADS):
    if f.endswith(".m4a"):
        name = f[:-4]
        meta_path = os.path.join(DOWNLOADS, f"{name}.json")
        if os.path.exists(meta_path):
            continue  # 已有metadata，跳过

        full_path = os.path.join(DOWNLOADS, f)
        media = instance.media_new(full_path)
        media.parse()
        time.sleep(0.5)
        duration = player.get_length()  # 毫秒
        if duration > 0:
            meta = {"author": "", "duration": duration // 1000}
            with open(meta_path, "w", encoding="utf-8") as fp:
                json.dump(meta, fp, ensure_ascii=False)
            count += 1
            print(f"✅ {name}  →  {duration // 1000}秒")

print(f"\n补全完成: {count} 首")
