import 'package:file_picker/file_picker.dart';

import 'playlist_cover_manager.dart';

/// Opens the platform image picker and immediately moves the selected image
/// into GoMusic's managed cover directory.
class PlaylistCoverPicker {
  final FilePicker filePicker;
  final PlaylistCoverManager coverManager;

  PlaylistCoverPicker({
    FilePicker? filePicker,
    PlaylistCoverManager? coverManager,
  }) : filePicker = filePicker ?? FilePicker.platform,
       coverManager = coverManager ?? PlaylistCoverManager();

  Future<String?> pickAndCopy({required String ownerId}) async {
    final result = await filePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
      dialogTitle: '选择封面图片',
    );
    final selected = result?.files.firstOrNull;
    final path = selected?.path;
    if (path == null || path.isEmpty) return null;
    return coverManager.copyLocalCover(path, ownerId: ownerId);
  }
}
