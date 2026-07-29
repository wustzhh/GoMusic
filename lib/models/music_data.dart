/// 歌曲数据模型
class Song {
  final String id;
  final String title;
  final String uploader;
  final Duration duration;
  final String? coverUrl;
  final bool hasVideo;
  final String bvid;

  // 原始信息（保留B站源信息）
  final String originalUrl;
  final String originalTitle;
  final String originalAuthor;

  const Song({
    required this.id,
    required this.title,
    required this.uploader,
    required this.duration,
    this.coverUrl,
    this.hasVideo = false,
    this.bvid = '',
    this.originalUrl = '',
    this.originalTitle = '',
    this.originalAuthor = '',
  });

  String get durationText {
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// 播放列表模型
class Playlist {
  final String id;
  final String name;
  final String icon;
  final List<Song> songs;

  const Playlist({
    required this.id,
    required this.name,
    required this.icon,
    required this.songs,
  });
}

/// 下载记录模型
class DownloadRecord {
  final String id;
  final String title;
  final String url;
  final bool downloadVideo;
  final double progress; // 0.0 ~ 1.0
  final DownloadStatus status;
  final bool hasAudio;
  final bool hasVideo;
  final String? fileSize;

  const DownloadRecord({
    required this.id,
    required this.title,
    required this.url,
    this.downloadVideo = false,
    this.progress = 0.0,
    this.status = DownloadStatus.pending,
    this.hasAudio = false,
    this.hasVideo = false,
    this.fileSize,
  });
}

enum DownloadStatus { pending, downloading, completed, failed }

// ============================================================
// 假数据
// ============================================================

final List<Song> mockAllSongs = [
  Song(id: '1', title: '夜曲', uploader: '周杰伦', duration: Duration(minutes: 3, seconds: 42), hasVideo: true, bvid: 'BV1xx411c7mD'),
  Song(id: '2', title: '晴天', uploader: '周杰伦', duration: Duration(minutes: 4, seconds: 29), hasVideo: false, bvid: ''),
  Song(id: '3', title: '起风了', uploader: '买辣椒也用券', duration: Duration(minutes: 5, seconds: 15), hasVideo: true, bvid: 'BV1YW41127cV'),
  Song(id: '4', title: 'Lemon', uploader: '米津玄师', duration: Duration(minutes: 4, seconds: 16), hasVideo: true, bvid: 'BV1Ht41147fM'),
  Song(id: '5', title: '打上花火', uploader: 'DAOKO × 米津玄师', duration: Duration(minutes: 4, seconds: 50), hasVideo: false, bvid: ''),
  Song(id: '6', title: '前前前世', uploader: 'RADWIMPS', duration: Duration(minutes: 4, seconds: 36), hasVideo: true, bvid: 'BV1Ms411k7sV'),
  Song(id: '7', title: 'なんでもないや', uploader: 'RADWIMPS', duration: Duration(minutes: 5, seconds: 46), hasVideo: false, bvid: ''),
  Song(id: '8', title: 'スパークル', uploader: 'RADWIMPS', duration: Duration(minutes: 6, seconds: 50), hasVideo: true, bvid: 'BV1Vs41117BY'),
  Song(id: '9', title: 'アイネクライネ', uploader: '米津玄师', duration: Duration(minutes: 4, seconds: 10), hasVideo: false, bvid: ''),
  Song(id: '10', title: 'LOSER', uploader: '米津玄师', duration: Duration(minutes: 4, seconds: 3), hasVideo: true, bvid: 'BV1kx41117fW'),
  Song(id: '11', title: 'Flamingo', uploader: '米津玄师', duration: Duration(minutes: 3, seconds: 35), hasVideo: false, bvid: ''),
  Song(id: '12', title: '千本桜', uploader: '黒うさP', duration: Duration(minutes: 4, seconds: 3), hasVideo: true, bvid: 'BV1hx411c7Vw'),
];

final List<Playlist> mockPlaylists = [
  Playlist(id: 'fav', name: '我的收藏', icon: '❤️', songs: mockAllSongs.sublist(0, 6)),
  Playlist(id: 'like', name: '我喜欢', icon: '👍', songs: mockAllSongs.sublist(2, 6)),
  Playlist(id: 'recent', name: '最近播放', icon: '🕐', songs: mockAllSongs.sublist(4, 10)),
  Playlist(id: 'all', name: '全部歌曲', icon: '📋', songs: mockAllSongs),
];
