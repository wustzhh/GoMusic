// Real libmpv verification: opens a local audio file, raises native volume to 200
// and confirms playback proceeds (no audio filter init failure).
import 'dart:async';
import 'dart:io';
import 'package:media_kit/media_kit.dart';

Future<void> main() async {
  MediaKit.ensureInitialized(libmpv: r'D:\pyProj\GoMusic\build\windows\x64\libmpv\libmpv-2.dll');
  final player = Player();
  final errors = <String>[];
  player.stream.error.listen(errors.add);
  var lastPos = Duration.zero;
  player.stream.position.listen((p) => lastPos = p);

  await player.open(Media('file:///D:/pyProj/GoMusic/downloads/BV1ds411f7Hy.m4a'), play: true);
  await Future<void>.delayed(const Duration(seconds: 1));

  final dynamic platform = player.platform;
  await platform.setProperty('volume-max', '200');
  await player.setVolume(200);

  await Future<void>.delayed(const Duration(seconds: 3));

  final state = player.state;
  // (cleanup line removed)
  final filterFail = errors.any((e) => e.contains('Audio filter initialized failed'));

  stdout.writeln('RESULT playing=${state.playing} positionMs=${state.position.inMilliseconds} lastPosMs=${lastPos.inMilliseconds} volume=${state.volume} errors=${errors.length} filterFail=$filterFail');
  stdout.writeln('SAMPLES_OK=${state.position.inMilliseconds > 500 || lastPos.inMilliseconds > 500}');

  await player.dispose();
  exit(filterFail || (state.position.inMilliseconds <= 500 && lastPos.inMilliseconds <= 500) ? 1 : 0);
}
