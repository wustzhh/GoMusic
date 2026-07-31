"""音乐播放器 — python-vlc 封装"""
try:
    import vlc
    HAS_VLC = True
except FileNotFoundError:
    HAS_VLC = False
import time
from models import Song


class MusicPlayer:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._init()
        return cls._instance

    def _init(self):
        self._vlc = None
        self._player = None
        self._current_song: Song | None = None
        self._queue: list[Song] = []
        self._index = 0
        self._mode = "loop"
        self._callbacks = {"song_changed": [], "state_changed": [], "position": []}

        if HAS_VLC:
            self._vlc = vlc.Instance("--no-xlib")
            self._player = self._vlc.media_player_new()
            self._vlc.event_manager().event_attach(
                vlc.EventType.MediaPlayerEndReached, self._on_end)

    def _check(self) -> bool:
        if not HAS_VLC:
            print("⚠ VLC 未安装，播放功能不可用。请安装 VLC: https://www.videolan.org/vlc/")
            return False
        return True

    def _on_end(self, event):
        self.next()

    @property
    def current_song(self) -> Song | None:
        return self._current_song

    @property
    def queue(self) -> list[Song]:
        return list(self._queue)

    @property
    def queue_index(self) -> int:
        return self._index

    @property
    def mode(self) -> str:
        return self._mode

    @mode.setter
    def mode(self, v: str):
        self._mode = v
        self._notify("state_changed")

    @property
    def is_playing(self) -> bool:
        return self._player.is_playing() if self._player else False

    @property
    def position(self) -> int:
        return self._player.get_time() if self._player else 0

    @property
    def duration(self) -> int:
        return self._player.get_length() if self._player else 0

    def play(self, song: Song):
        if not self._check(): return
        self._current_song = song
        media = self._vlc.media_new(song.filepath)
        media.parse()
        self._player.set_media(media)
        self._player.play()
        real_dur = self._player.get_length()
        if real_dur > 0 and song.duration <= 0:
            song.duration = real_dur // 1000
            from models import save_song_meta
            save_song_meta(song)
        self._notify("song_changed")
        self._notify("state_changed")

    def pause(self):
        if self._player: self._player.pause()
        self._notify("state_changed")

    def resume(self):
        if self._player: self._player.play()
        self._notify("state_changed")

    def toggle(self):
        if self.is_playing: self.pause()
        else: self.resume()

    def stop(self):
        if self._player: self._player.stop()

    def seek(self, ms: int):
        if self._player: self._player.set_time(ms)

    def set_queue(self, songs: list[Song], start_index: int = 0):
        self._queue = list(songs)
        self._index = start_index

    def next(self):
        if not self._queue: return
        import random
        if self._mode == "repeat_one": self.seek(0); return
        if self._mode == "shuffle": self._index = random.randint(0, len(self._queue) - 1)
        else: self._index = (self._index + 1) % len(self._queue)
        self.play(self._queue[self._index])

    def prev(self):
        if not self._queue: return
        if self.position > 3000: self.seek(0); return
        self._index = (self._index - 1) % len(self._queue)
        self.play(self._queue[self._index])

    def remove_from_queue(self, index: int):
        if 0 <= index < len(self._queue):
            self._queue.pop(index)
            if index < self._index: self._index -= 1

    def add_callback(self, event: str, cb):
        self._callbacks[event].append(cb)

    def _notify(self, event: str):
        for cb in self._callbacks[event]: cb()

    def start_position_timer(self, interval_ms: int = 500):
        from PySide6.QtCore import QTimer
        self._timer = QTimer()
        self._timer.timeout.connect(lambda: self._notify("position"))
        self._timer.start(interval_ms)
