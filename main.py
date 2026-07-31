"""GoMusic — B站音频下载 + 本地音乐播放器"""
import sys
from pathlib import Path
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QStackedWidget, QToolBar,
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton,
    QLineEdit, QListWidget, QListWidgetItem, QSlider, QProgressBar,
    QMessageBox, QDialog, QCheckBox, QComboBox, QFileDialog, QFrame,
    QSplitter, QScrollArea, QSizePolicy
)
from PySide6.QtCore import Qt, QTimer, QUrl, QThread, Signal
from PySide6.QtGui import QPixmap, QIcon, QFont

from models import (
    init_db, scan_local_songs, save_song_meta, Song,
    get_favorites, toggle_favorite,
    get_playlists, create_playlist, add_to_playlist, get_playlist_songs,
    get_setting, set_setting, DOWNLOADS_DIR
)
from downloader import extract_info, download_audio, extract_collection
from player import MusicPlayer

STYLE = """
QMainWindow { background-color: #1a1a2e; }
QWidget { color: #e0e0e0; font-size: 14px; }
QLineEdit {
    background: #16213e; border: 1px solid #0f3460; border-radius: 8px;
    padding: 8px; color: white;
}
QPushButton {
    background: #0f3460; border: none; border-radius: 8px;
    padding: 10px 20px; color: white; font-weight: bold;
}
QPushButton:hover { background: #533483; }
QPushButton:pressed { background: #e94560; }
QListWidget { background: #16213e; border: none; border-radius: 8px; }
QListWidget::item { padding: 8px; border-bottom: 1px solid #0f3460; }
QListWidget::item:selected { background: #533483; }
QProgressBar { border: none; border-radius: 4px; background: #16213e; }
QProgressBar::chunk { background: #e94560; border-radius: 4px; }
QSlider::groove:horizontal { height: 4px; background: #0f3460; border-radius: 2px; }
QSlider::handle:horizontal { background: #e94560; width: 14px; height: 14px; margin: -5px 0; border-radius: 7px; }
QComboBox { background: #16213e; border: 1px solid #0f3460; border-radius: 6px; padding: 6px; color: white; }
QFrame#bottomBar { background: #0f3460; border-top: 1px solid #533483; }
QLabel#nowPlaying { font-size: 13px; color: #e94560; }
"""


class GoMusic(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("GoMusic")
        self.setGeometry(200, 60, 420, 780)
        self.setStyleSheet(STYLE)

        init_db()
        self.player = MusicPlayer()
        self.player.start_position_timer(500)

        # 主布局
        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # 页面栈
        self.stack = QStackedWidget()
        self.download_page = DownloadPage(self)
        self.playlist_page = PlaylistPage(self)
        self.settings_page = SettingsPage(self)
        self.stack.addWidget(self.download_page)
        self.stack.addWidget(self.playlist_page)
        self.stack.addWidget(self.settings_page)
        layout.addWidget(self.stack)

        # 迷你播放条
        self.mini_bar = MiniPlayerBar(self)
        layout.addWidget(self.mini_bar)

        # 底部导航
        nav = QToolBar()
        nav.setMovable(False)
        nav.setStyleSheet("QToolBar { background: #0f3460; spacing: 0; padding: 4px; }")
        for i, (name, icon) in enumerate([("📥 下载", 0), ("🎵 播放", 1), ("⚙ 设置", 2)]):
            btn = QPushButton(name)
            btn.setStyleSheet("QPushButton { background: transparent; font-size: 15px; padding: 12px; }"
                              "QPushButton:hover { color: #e94560; }")
            btn.clicked.connect(lambda checked, idx=i: self.stack.setCurrentIndex(idx))
            nav.addWidget(btn)
        layout.addWidget(nav)

        self.stack.setCurrentIndex(0)

        # 播放器回调
        self.player.add_callback("song_changed", self.mini_bar.refresh)
        self.player.add_callback("state_changed", self.mini_bar.refresh)
        self.player.add_callback("position", self.mini_bar.update_position)


# ====================== 迷你播放条 ======================

class MiniPlayerBar(QFrame):
    def __init__(self, main: GoMusic):
        super().__init__()
        self.setObjectName("bottomBar")
        self.setFixedHeight(52)
        self.main = main
        layout = QHBoxLayout(self)
        layout.setContentsMargins(12, 4, 12, 4)

        self.title_label = QLabel("未在播放")
        self.title_label.setObjectName("nowPlaying")
        layout.addWidget(self.title_label, 1)

        self.play_btn = QPushButton("▶")
        self.play_btn.setFixedSize(36, 36)
        self.play_btn.clicked.connect(lambda: self.main.player.toggle())
        layout.addWidget(self.play_btn)

        self.progress = QProgressBar()
        self.progress.setFixedHeight(2)
        self.progress.setTextVisible(False)
        layout.insertWidget(1, self.progress)
        self.progress.hide()

    def refresh(self):
        song = self.main.player.current_song
        if song:
            self.title_label.setText(f"🎵 {song.title}")
            self.play_btn.setText("⏸" if self.main.player.is_playing else "▶")
            dur = self.main.player.duration
            if dur > 0:
                self.progress.show()
                self.progress.setMaximum(dur)
        else:
            self.title_label.setText("未在播放")
            self.play_btn.setText("▶")
            self.progress.hide()

    def update_position(self):
        pos = self.main.player.position
        dur = self.main.player.duration
        if dur > 0:
            self.progress.setValue(pos)


# ====================== 下载页 ======================

class DownloadPage(QWidget):
    def __init__(self, main: GoMusic):
        super().__init__()
        self.main = main
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)

        # URL 输入
        self.url_input = QLineEdit()
        self.url_input.setPlaceholderText("粘贴B站视频链接...")
        layout.addWidget(self.url_input)

        self.parse_btn = QPushButton("🔍 解析")
        self.parse_btn.clicked.connect(self._parse)
        layout.addWidget(self.parse_btn)

        # 信息显示
        self.info_label = QLabel("")
        self.info_label.setWordWrap(True)
        self.info_label.setVisible(False)
        layout.addWidget(self.info_label)

        # 进度条
        self.progress = QProgressBar()
        self.progress.setVisible(False)
        layout.addWidget(self.progress)

        # 下载按钮
        self.dl_btn = QPushButton("⬇ 下载音频")
        self.dl_btn.clicked.connect(self._download)
        self.dl_btn.setVisible(False)
        layout.addWidget(self.dl_btn)

        layout.addStretch()

    def _parse(self):
        url = self.url_input.text().strip()
        if not url:
            return
        self.parse_btn.setEnabled(False)
        self.parse_btn.setText("解析中...")

        # 检查是否收藏夹
        if "/list/ml" in url or "favlist" in url or ("fid=" in url and "space.bilibili.com" in url):
            videos = extract_collection(url)
            if videos:
                self._show_collection(videos)
                self.parse_btn.setEnabled(True)
                self.parse_btn.setText("🔍 解析")
                return

        self._current_info = extract_info(url)
        self.parse_btn.setEnabled(True)
        self.parse_btn.setText("🔍 解析")
        if self._current_info:
            t = self._current_info
            self.info_label.setText(
                f"🎬 {t.get('title','')}\n"
                f"👤 {t.get('uploader','')}\n"
                f"⏱ {t.get('duration',0)}秒"
            )
            self.info_label.setVisible(True)
            self.dl_btn.setVisible(True)
        else:
            QMessageBox.warning(self, "错误", "解析失败")

    def _show_collection(self, videos: list[dict]):
        self.info_label.setText(f"收藏夹 · {len(videos)} 个视频")
        self.info_label.setVisible(True)
        self._collection = videos
        self.dl_btn.setText(f"⬇ 一键下载全部 ({len(videos)}首)")
        self.dl_btn.setVisible(True)

    def _download(self):
        url = self.url_input.text().strip()
        if hasattr(self, "_collection"):
            self._batch_download(self._collection)
            return

        if not hasattr(self, "_current_info") or not self._current_info:
            return
        self.dl_btn.setEnabled(False)
        self.progress.setVisible(True)
        info = self._current_info
        song = download_audio(url, str(DOWNLOADS_DIR))
        self.dl_btn.setEnabled(True)
        self.progress.setVisible(False)
        if song:
            QMessageBox.information(self, "完成", f"已下载: {song.title}")
        else:
            QMessageBox.warning(self, "失败", "下载失败")

    def _batch_download(self, videos: list[dict]):
        self.dl_btn.setEnabled(False)
        self.progress.setVisible(True)
        self.progress.setMaximum(len(videos))
        ok = 0
        for i, v in enumerate(videos):
            song = download_audio(v["url"], str(DOWNLOADS_DIR))
            if song:
                ok += 1
            self.progress.setValue(i + 1)
        self.dl_btn.setEnabled(True)
        QMessageBox.information(self, "完成", f"批量下载: {ok}/{len(videos)}")


# ====================== 播放列表页 ======================

class PlaylistPage(QWidget):
    def __init__(self, main: GoMusic):
        super().__init__()
        self.main = main
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)

        self.list_widget = QListWidget()
        self.list_widget.itemDoubleClicked.connect(self._play_item)
        layout.addWidget(self.list_widget)

        refresh_btn = QPushButton("🔄 刷新")
        refresh_btn.clicked.connect(self._load)
        layout.addWidget(refresh_btn)

        self._load()

    def _load(self):
        self.list_widget.clear()
        songs = scan_local_songs()
        favs = get_favorites()
        for song in songs:
            label = f"  {song.title}"
            if song.uploader:
                label += f"  ·  {song.uploader}"
            if song.duration > 0:
                label += f"  ·  {song.duration_text}"
            if song.filepath in favs:
                label += "  ❤"
            item = QListWidgetItem(label)
            item.setData(Qt.UserRole, song)
            self.list_widget.addItem(item)

    def _play_item(self, item: QListWidgetItem):
        song = item.data(Qt.UserRole)
        if song:
            songs = scan_local_songs()
            self.main.player.set_queue(songs)
            self.main.player.play(song)


# ====================== 设置页 ======================

class SettingsPage(QWidget):
    def __init__(self, main: GoMusic):
        super().__init__()
        self.main = main
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)

        path_layout = QHBoxLayout()
        self.path_label = QLabel(f"下载路径: {get_setting('download_path', str(DOWNLOADS_DIR))}")
        path_layout.addWidget(self.path_label)
        change_btn = QPushButton("修改")
        change_btn.clicked.connect(self._change_path)
        path_layout.addWidget(change_btn)
        layout.addLayout(path_layout)

        layout.addStretch()


    def _change_path(self):
        d = QFileDialog.getExistingDirectory(self, "选择下载目录")
        if d:
            set_setting("download_path", d)
            self.path_label.setText(f"下载路径: {d}")


# ====================== 入口 ======================

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyleSheet(STYLE)
    window = GoMusic()
    window.show()
    sys.exit(app.exec())
