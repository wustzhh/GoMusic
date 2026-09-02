// Real libmpv verification: opens a local audio file, changes volume to 200
// without reopening the media, and confirms mpv reports the boosted value.
import 'dart:async';
import 'dart:io';
import 'package:media_kit/media_kit.dart';

Future<void> main() async {
  MediaKit.ensureInitialized(
    libmpv: r'D:\GitHubProject\GoMusic\build\windows\x64\libmpv\libmpv-2.dll',
  );
  final player = Player();
  final errors = <String>[];
  player.stream.error.listen(errors.add);
  var lastPos = Duration.zero;
  player.stream.position.listen((p) => lastPos = p);

  await player.open(
    Media('file:///D:/GitHubProject/GoMusic/downloads/BV118411B7XU.m4a'),
    play: true,
  );
  await Future<void>.delayed(const Duration(seconds: 1));
  await player.seek(const Duration(seconds: 12));

  final dynamic platform = player.platform;
  await platform.setProperty('volume-max', '200');
  await player.setVolume(200);

  await Future<void>.delayed(const Duration(seconds: 1));

  final state = player.state;
  final reportedMax = await platform.getProperty('volume-max');
  final reportedVolume = await platform.getProperty('volume');
  final reportedVolumeValue = double.tryParse(reportedVolume);
  final filterFail = errors.any(
    (e) => e.contains('Audio filter initialized failed'),
  );

  stdout.writeln(
    'RESULT playing=${state.playing} positionMs=${state.position.inMilliseconds} '
    'lastPosMs=${lastPos.inMilliseconds} volume=${state.volume} '
    'reportedMax=$reportedMax reportedVolume=$reportedVolume '
    'errors=${errors.length} filterFail=$filterFail',
  );
  final samplesOk =
      state.position.inMilliseconds >= 12000 &&
      lastPos.inMilliseconds >= 12000 &&
      reportedVolumeValue == 200.0;
  stdout.writeln('SAMPLES_OK=$samplesOk');

  await player.dispose();
  exit(
    filterFail ||
            state.position.inMilliseconds < 12000 ||
            lastPos.inMilliseconds < 12000 ||
            reportedVolumeValue != 200.0
        ? 1
        : 0,
  );
}
