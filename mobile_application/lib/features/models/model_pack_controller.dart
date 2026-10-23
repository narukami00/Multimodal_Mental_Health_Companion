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

  static const downloadFailed = "Couldn't get it just now. Check that your companion server is on and connected, then try again.";

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
    final ok = await store.download(onProgress: (p) {
      if (_disposed) return;
      progress = p;
      notifyListeners();
    });
    if (_disposed) return;
    downloading = false;
    message = ok ? null : downloadFailed;
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
