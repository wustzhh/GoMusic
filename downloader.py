"""B站下载器 — yt-dlp 封装"""
import yt_dlp
from pathlib import Path
from models import Song, save_song_meta


def extract_info(url: str) -> dict | None:
    """解析B站视频信息（不下载）"""
    opts = {
        "quiet": True,
        "no_warnings": True,
        "extract_flat": False,
    }
    with yt_dlp.YoutubeDL(opts) as ydl:
        try:
            return ydl.extract_info(url, download=False)
        except Exception:
            return None


def download_audio(url: str, output_dir: str, name: str = None,
                   progress_callback=None) -> Song | None:
    """下载音频 + 封面，返回 Song 对象"""
    opts = {
        "format": "bestaudio/best",
        "outtmpl": str(Path(output_dir) / "%(title)s.%(ext)s"),
        "postprocessors": [
            {"key": "FFmpegExtractAudio", "preferredcodec": "m4a"},
            {"key": "FFmpegMetadata"},
            {"key": "EmbedThumbnail"},
        ],
        "writethumbnail": True,
        "quiet": True,
        "no_warnings": True,
        "progress_hooks": [progress_callback] if progress_callback else [],
    }

    with yt_dlp.YoutubeDL(opts) as ydl:
        try:
            info = ydl.extract_info(url, download=True)
            title = info.get("title", "unknown")
            duration = int(info.get("duration", 0))
            uploader = info.get("uploader", "")
            bvid = info.get("id", "")

            # 找到下载的文件
            outtmpl = str(Path(output_dir) / f"{title}")
            for ext in (".m4a", ".mp3", ".opus", ".aac"):
                fp = Path(outtmpl + ext)
                if fp.exists():
                    cover = str(Path(output_dir) / f"{title}.jpg")
                    song = Song(
                        filepath=str(fp),
                        title=title,
                        uploader=uploader,
                        duration=duration,
                        cover_path=cover,
                        bvid=bvid,
                        url=url,
                    )
                    save_song_meta(song)
                    return song
        except Exception:
            pass
    return None


def extract_collection(url: str) -> list[dict]:
    """解析收藏夹/合集，返回视频列表"""
    opts = {"quiet": True, "no_warnings": True, "extract_flat": True}
    with yt_dlp.YoutubeDL(opts) as ydl:
        try:
            info = ydl.extract_info(url, download=False)
            if "entries" in info:
                return [{"title": e.get("title", ""), "url": e.get("url", ""),
                         "duration": e.get("duration", 0)} for e in info["entries"]]
        except Exception:
            pass
    return []
