import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Playlist exposes optional cover and last-played fields', () {
    final playedAt = DateTime(2026, 8, 31, 12, 30);
    const playlist = Playlist(
      id: 'p1',
      name: '收藏',
      icon: '🎵',
      songs: [],
      coverPath: 'covers/p1.jpg',
      lastPlayedAt: null,
    );

    expect(playlist.coverPath, 'covers/p1.jpg');
    expect(playlist.lastPlayedAt, isNull);
    expect(
      Playlist(
        id: playlist.id,
        name: playlist.name,
        icon: playlist.icon,
        songs: playlist.songs,
        lastPlayedAt: playedAt,
      ).lastPlayedAt,
      playedAt,
    );
  });

  test('reads legacy four-field playlists and new metadata fields', () async {
    SharedPreferences.setMockInitialValues({
      'custom_playlists': [
        'old|||旧歌单|||📁|||["BV-old"]',
        'played-late|||晚播放|||🎧|||["BV-late"]|||late.jpg|||2026-08-31T12:00:00.000Z',
        'played-early|||早播放|||🎧|||["BV-early"]|||early.jpg|||2026-08-30T12:00:00.000Z',
        'new-unplayed|||未播放|||🎵|||[]',
      ],
    });

    final playlists = await PlaylistService.getPlaylists();

    expect(playlists.map((p) => p.id), [
      'played-late',
      'played-early',
      'old',
      'new-unplayed',
    ]);
    expect(playlists[0].coverPath, 'late.jpg');
    expect(
      playlists[0].lastPlayedAt,
      DateTime.parse('2026-08-31T12:00:00.000Z'),
    );
    expect(playlists[2].coverPath, isNull);
    expect(playlists[2].lastPlayedAt, isNull);
  });

  test(
    'markPlayed and setPlaylistCover persist without changing songs',
    () async {
      SharedPreferences.setMockInitialValues({
        'custom_playlists': ['p1|||歌单|||🎵|||["BV1","BV2"]'],
      });
      final at = DateTime(2026, 8, 31, 15, 45);

      await PlaylistService.setPlaylistCover('p1', 'playlist_covers/p1.png');
      await PlaylistService.markPlayed('p1', at: at);

      final playlist = (await PlaylistService.getPlaylists()).single;
      expect(playlist.coverPath, 'playlist_covers/p1.png');
      expect(playlist.lastPlayedAt, at);
      expect(playlist.songs.map((song) => song.bvid), ['BV1', 'BV2']);
    },
  );

  test('deletePlaylist removes only the playlist record', () async {
    SharedPreferences.setMockInitialValues({
      'custom_playlists': ['p1|||要删|||🎵|||["BV1"]', 'p2|||保留|||🎵|||["BV2"]'],
      'favorites': ['BV1'],
    });

    await PlaylistService.deletePlaylist('p1');

    expect((await PlaylistService.getPlaylists()).map((p) => p.id), ['p2']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('favorites'), ['BV1']);
  });
}
