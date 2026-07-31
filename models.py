"""数据模型"""
from dataclasses import dataclass, field
from pathlib import Path
import json
import sqlite3
import os

DOWNLOADS_DIR = Path(__file__).parent / "downloads"
DOWNLOADS_DIR.mkdir(exist_ok=True)


@dataclass
class Song:
    filepath: str
    title: str = ""
    uploader: str = ""
    duration: int = 0       # 秒
    cover_path: str = ""
    bvid: str = ""
    url: str = ""

    @property
    def duration_text(self) -> str:
        if self.duration <= 0:
            return ""
        m, s = divmod(self.duration, 60)
        return f"{m:02d}:{s:02d}"


# ========== SQLite ==========

DB_PATH = Path(__file__).parent / "gomusic.db"


def get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(str(DB_PATH))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    db = get_db()
    db.execute("""
        CREATE TABLE IF NOT EXISTS songs (
            filepath TEXT PRIMARY KEY,
            title TEXT,
            uploader TEXT,
            duration INTEGER DEFAULT 0,
            cover_path TEXT,
            bvid TEXT,
            url TEXT
        )
    """)
    db.execute("""
        CREATE TABLE IF NOT EXISTS playlists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    db.execute("""
        CREATE TABLE IF NOT EXISTS playlist_songs (
            playlist_id INTEGER,
            filepath TEXT,
            sort_order INTEGER,
            PRIMARY KEY (playlist_id, filepath),
            FOREIGN KEY (playlist_id) REFERENCES playlists(id)
        )
    """)
    db.execute("""
        CREATE TABLE IF NOT EXISTS favorites (
            filepath TEXT PRIMARY KEY,
            added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    db.execute("""
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """)
    # 默认下载路径
    db.execute("INSERT OR IGNORE INTO settings(key,value) VALUES('download_path',?)",
               (str(DOWNLOADS_DIR),))
    db.commit()
    db.close()


# ========== 扫描本地 ==========

def scan_local_songs(directory: str = None) -> list[Song]:
    if directory is None:
        directory = str(DOWNLOADS_DIR)
    songs = []
    db = get_db()
    for ext in (".m4a", ".mp3", ".aac", ".flac", ".wav", ".ogg"):
        for f in Path(directory).glob(f"*{ext}"):
            name = f.stem
            cover = str(f.with_suffix(".jpg"))
            if not os.path.exists(cover):
                cover = ""
            # 从数据库补元数据
            row = db.execute("SELECT * FROM songs WHERE filepath=?", (str(f),)).fetchone()
            songs.append(Song(
                filepath=str(f),
                title=row["title"] if row else name,
                uploader=row["uploader"] if row else "",
                duration=row["duration"] if row else 0,
                cover_path=cover,
                bvid=row["bvid"] if row else "",
                url=row["url"] if row else "",
            ))
    db.close()
    return songs


def save_song_meta(song: Song):
    db = get_db()
    db.execute("""
        INSERT OR REPLACE INTO songs (filepath, title, uploader, duration, cover_path, bvid, url)
        VALUES (?,?,?,?,?,?,?)
    """, (song.filepath, song.title, song.uploader, song.duration,
          song.cover_path, song.bvid, song.url))
    db.commit()
    db.close()


# ========== 收藏夹 ==========

def get_favorites() -> set[str]:
    db = get_db()
    rows = db.execute("SELECT filepath FROM favorites").fetchall()
    db.close()
    return {r["filepath"] for r in rows}


def toggle_favorite(filepath: str):
    db = get_db()
    exists = db.execute("SELECT 1 FROM favorites WHERE filepath=?", (filepath,)).fetchone()
    if exists:
        db.execute("DELETE FROM favorites WHERE filepath=?", (filepath,))
    else:
        db.execute("INSERT INTO favorites (filepath) VALUES (?)", (filepath,))
    db.commit()
    db.close()


# ========== 歌单 ==========

def get_playlists() -> list[dict]:
    db = get_db()
    rows = db.execute("SELECT * FROM playlists ORDER BY id").fetchall()
    db.close()
    return [{"id": r["id"], "name": r["name"]} for r in rows]


def create_playlist(name: str) -> int:
    db = get_db()
    db.execute("INSERT OR IGNORE INTO playlists (name) VALUES (?)", (name,))
    row = db.execute("SELECT id FROM playlists WHERE name=?", (name,)).fetchone()
    db.commit()
    db.close()
    return row["id"] if row else 0


def add_to_playlist(playlist_id: int, filepath: str):
    db = get_db()
    count = db.execute("SELECT COUNT(*) FROM playlist_songs WHERE playlist_id=?",
                       (playlist_id,)).fetchone()[0]
    db.execute("INSERT OR IGNORE INTO playlist_songs (playlist_id, filepath, sort_order) VALUES (?,?,?)",
               (playlist_id, filepath, count))
    db.commit()
    db.close()


def get_playlist_songs(playlist_id: int) -> list[str]:
    db = get_db()
    rows = db.execute("SELECT filepath FROM playlist_songs WHERE playlist_id=? ORDER BY sort_order",
                      (playlist_id,)).fetchall()
    db.close()
    return [r["filepath"] for r in rows]


# ========== 设置 ==========

def get_setting(key: str, default: str = "") -> str:
    db = get_db()
    row = db.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    db.close()
    return row["value"] if row else default


def set_setting(key: str, value: str):
    db = get_db()
    db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?,?)", (key, value))
    db.commit()
    db.close()
