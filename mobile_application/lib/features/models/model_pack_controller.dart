import 'package:flutter/foundation.dart';

import '../../services/model_pack_store.dart';

/// What the screens need to know about one on-device model pack: is it installed, how big, is a download running.
/// The failure text is always a plain sentence for the person, never an error name.
class ModelPackController extends ChangeNotifier {
  ModelPackController(this.store) {
    store.addListener(_onStoreChanged);
    refresh();
  }

  final ModelPackStore store;

  /// null until the first look at the phone's storage has finished.
  bool? installed;
  int? bytes;
  bool downloading = false;
  double progress = 0;
  String? message;
  bool _disposed = false;

  /// What to tell the person when a download did not finish: the real reason, in one calm sentence.
  static String explainDownload(ModelDownload result, {int? megabytes}) => switch (result) {
        ModelDownload.installed => '',
        ModelDownload.serverAway => "Couldn't reach your companion server. Check that it's on and connected, then try again.",
        ModelDownload.notOnServer => "Your companion server doesn't have this set up yet. Ask whoever runs it to add it, then try again.",
        ModelDownload.interrupted => 'The download was interrupted, so nothing was kept. Try again, ideally on Wi-Fi.',
        ModelDownload.noSpace => "There isn't enough free space on this phone${megabytes == null ? '' : ' (about $megabytes MB are needed)'}. "
            'Free some up and try again.',
      };

  void _onStoreChanged() => refresh();

  Future<void> refresh() async {
    final size = await store.installedBytes();
    if (_disposed) return;
    installed = size != null;
    bytes = size;
    notifyListeners();
  }

  Future<void> download() async {
    if (downloading) return;
    downloading = true;
    progress = 0;
    message = null;
    notifyListeners();
    final result = await store.downloadResult(onProgress: (p) {
      if (_disposed) return;
      progress = p;
      notifyListeners();
    });
    if (_disposed) return;
    downloading = false;
    message = result == ModelDownload.installed ? null : explainDownload(result, megabytes: store.sizeMegabytes);
    await refresh();
  }

  Future<void> remove() async {
    await store.remove();
    message = null;
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    store.removeListener(_onStoreChanged);
    super.dispose();
  }
}
