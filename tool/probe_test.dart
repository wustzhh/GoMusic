import 'package:gomusic/services/bilibili_api.dart';

void main() async {
  final api = BilibiliApi();
  final t0 = DateTime.now();
  final info = await api.getVideoInfo('https://www.bilibili.com/video/BV1EPqpYFExo');
  print('耗时: ${DateTime.now().difference(t0).inSeconds}s');
  print('title: ${info?.title}');
  print('audioSize: ${info?.audioSize}');
  print('audioSizeText: ${info?.audioSizeText}');
}
