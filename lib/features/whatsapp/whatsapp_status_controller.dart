import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/status_message.dart';
import '../../core/notifications/media_notification_service.dart';
import '../../core/notifications/notification_permission_service.dart';
import '../../core/settings/app_settings_service.dart';
import '../../core/storage/media_library_service.dart';
import '../../core/storage/media_save_service.dart';
import '../../core/storage/saf_service.dart';
import '../../core/storage/status_archive_service.dart';
import '../../services/whatsapp/whatsapp_status_reader.dart';

const _prefsKey = 'whatsapp_status_folder';
final _galAlbum = albumNameForSource('WhatsApp');

class WhatsAppStatusState {
  const WhatsAppStatusState({
    this.checkingFolder = true,
    this.treeUri,
    this.items = const AsyncValue.loading(),
    this.archivedItems = const [],
    this.selectionMode = false,
    this.selectedUris = const {},
    this.saving = false,
    this.sharing = false,
    this.lastResultMessage,
  });

  final bool checkingFolder;
  final String? treeUri;

  /// Statuses read live from WhatsApp's `.Statuses` cache via SAF.
  final AsyncValue<List<StatusItem>> items;

  /// Private in-app archive copies (see [StatusArchiveService]) whose
  /// original is no longer in the fresh list. Empty when the archive is
  /// turned off. Shown in the WhatsApp screen's "Archived" tab.
  final List<StatusItem> archivedItems;

  /// Whether tapping a tile toggles selection instead of opening the full
  /// preview — same explicit Select/Cancel model as Library, entered/exited
  /// via a toolbar button rather than as a long-press side effect.
  final bool selectionMode;
  final Set<String> selectedUris;
  final bool saving;
  final bool sharing;
  final StatusMessage? lastResultMessage;

  bool get busy => saving || sharing;

  WhatsAppStatusState copyWith({
    bool? checkingFolder,
    String? treeUri,
    bool clearTreeUri = false,
    AsyncValue<List<StatusItem>>? items,
    List<StatusItem>? archivedItems,
    bool? selectionMode,
    Set<String>? selectedUris,
    bool? saving,
    bool? sharing,
    StatusMessage? lastResultMessage,
    bool clearLastResultMessage = false,
  }) {
    return WhatsAppStatusState(
      checkingFolder: checkingFolder ?? this.checkingFolder,
      treeUri: clearTreeUri ? null : (treeUri ?? this.treeUri),
      items: items ?? this.items,
      archivedItems: archivedItems ?? this.archivedItems,
      selectionMode: selectionMode ?? this.selectionMode,
      selectedUris: selectedUris ?? this.selectedUris,
      saving: saving ?? this.saving,
      sharing: sharing ?? this.sharing,
      lastResultMessage: clearLastResultMessage
          ? null
          : (lastResultMessage ?? this.lastResultMessage),
    );
  }
}

class WhatsAppStatusController extends StateNotifier<WhatsAppStatusState> {
  WhatsAppStatusController({
    SafService? safService,
    MediaSaveService? mediaSaveService,
    MediaNotificationService? mediaNotificationService,
    NotificationPermissionService? notificationPermissionService,
    StatusArchiveService? statusArchiveService,
    AppSettingsService? appSettingsService,
  }) : _safService = safService ?? SafService(),
       _safStream = SafStream(),
       _mediaSaveService = mediaSaveService ?? MediaSaveService(),
       _mediaNotificationService =
           mediaNotificationService ?? MediaNotificationService(),
       _notificationPermissionService =
           notificationPermissionService ?? NotificationPermissionService(),
       _statusArchiveService = statusArchiveService ?? StatusArchiveService(),
       _appSettingsService = appSettingsService ?? AppSettingsService(),
       super(const WhatsAppStatusState()) {
    _init();
  }

  final SafService _safService;
  final SafStream _safStream;
  final MediaSaveService _mediaSaveService;
  final MediaNotificationService _mediaNotificationService;
  final NotificationPermissionService _notificationPermissionService;
  final StatusArchiveService _statusArchiveService;
  final AppSettingsService _appSettingsService;

  Future<void> _init() async {
    final uri = await _safService.getPersistedTreeUri(_prefsKey);
    if (uri == null) {
      state = state.copyWith(checkingFolder: false);
    } else {
      state = state.copyWith(checkingFolder: false, treeUri: uri);
      await refresh();
    }
    unawaited(_purgeLegacyGalleryAlbumOnce());
  }

  /// Deletes the 0.3.4 "WhatsApp Archive" gallery album once, on first run
  /// after upgrading — that build leaked every viewed status into the
  /// gallery/Library. The archive is a private in-app copy now.
  Future<void> _purgeLegacyGalleryAlbumOnce() async {
    try {
      if (await _appSettingsService.getLegacyArchivePurged()) return;
      await _statusArchiveService.purgeLegacyGalleryAlbum();
      await _appSettingsService.setLegacyArchivePurged(true);
    } catch (_) {}
  }

  Future<void> pickFolder({required bool business}) async {
    final initialUri = business
        ? WhatsAppStatusReader.initialUriForWhatsAppBusiness
        : WhatsAppStatusReader.initialUriForWhatsApp;
    final uri = await _safService.pickAndPersistTreeUri(
      _prefsKey,
      initialUri: initialUri,
    );
    if (uri == null) return;
    state = state.copyWith(treeUri: uri, selectedUris: {});
    await refresh();
  }

  Future<void> forgetFolder() async {
    await _safService.forgetTreeUri(_prefsKey);
    state = const WhatsAppStatusState(checkingFolder: false);
  }

  Future<void> refresh() async {
    final treeUri = state.treeUri;
    if (treeUri == null) return;
    state = state.copyWith(items: const AsyncValue.loading());
    try {
      final files = await _safService.listFiles(treeUri);
      final statuses = WhatsAppStatusReader.filterStatusFiles(files);
      state = state.copyWith(items: AsyncValue.data(statuses));
      await _runArchive(statuses);
    } catch (error, stackTrace) {
      state = state.copyWith(items: AsyncValue.error(error, stackTrace));
    }
    // Always refresh the archived tab, even if the fresh list failed to
    // load — the two are independent stores.
    await _loadArchived();
  }

  /// Opportunistic WhatsApp-status archiving + retention cleanup — runs on
  /// every folder refresh when the user has opted in (Settings → WhatsApp).
  /// Archiving is silent: the copies just appear in the "Archived" tab.
  /// Wrapped so a failure here never disturbs the status list that already
  /// loaded.
  Future<void> _runArchive(List<StatusItem> statuses) async {
    try {
      final retention = await _appSettingsService.getStatusArchiveRetention();
      if (retention == StatusArchiveRetention.off) {
        await _statusArchiveService.purgeAll();
        return;
      }
      await _statusArchiveService.archiveNew(statuses);
      await _statusArchiveService.pruneExpired(retention.duration);
    } catch (_) {}
  }

  /// Loads the private archive into [WhatsAppStatusState.archivedItems],
  /// hiding any entry whose status is still live in the fresh list (each
  /// status shows once, preferring the live copy). Empty when the archive
  /// is off.
  Future<void> _loadArchived() async {
    try {
      final retention = await _appSettingsService.getStatusArchiveRetention();
      if (retention == StatusArchiveRetention.off) {
        state = state.copyWith(archivedItems: const []);
        return;
      }
      final archived = await _statusArchiveService.loadArchived();
      final freshNames = (state.items.valueOrNull ?? const <StatusItem>[])
          .map((s) => s.name)
          .toSet();
      state = state.copyWith(
        archivedItems:
            archived.where((a) => !freshNames.contains(a.name)).toList(),
      );
    } catch (_) {
      state = state.copyWith(archivedItems: const []);
    }
  }

  void enterSelectionMode() {
    state = state.copyWith(selectionMode: true, selectedUris: {});
  }

  /// Exits selection mode and clears the selection — the "cancel" action.
  void exitSelectionMode() {
    state = state.copyWith(selectionMode: false, selectedUris: {});
  }

  void toggleSelected(String uri) {
    final selected = {...state.selectedUris};
    if (!selected.remove(uri)) {
      selected.add(uri);
    }
    state = state.copyWith(selectedUris: selected);
  }

  /// Fresh + archived statuses combined — selection can span both tabs.
  List<StatusItem> get _allItems => [
    ...?state.items.valueOrNull,
    ...state.archivedItems,
  ];

  Future<void> saveSelected() async {
    if (state.selectedUris.isEmpty || state.busy) return;

    final toSave =
        _allItems.where((i) => state.selectedUris.contains(i.uri)).toList();
    if (toSave.isEmpty) return;
    state = state.copyWith(saving: true, clearLastResultMessage: true);

    // Best-effort: the save proceeds regardless of the outcome — denied
    // just means the "saved" notification below stays invisible.
    unawaited(_notificationPermissionService.ensureRequested());

    final tempDir = await getTemporaryDirectory();
    var succeeded = 0;
    var failed = 0;
    String? lastSavedContentUri;
    String? lastSavedMimeType;
    String? lastSavedName;

    for (final item in toSave) {
      // Archived items are already local files — save straight from the
      // archive, no SAF copy and nothing to clean up afterwards. Fresh
      // items must be pulled out of SAF into a temp file first.
      final archivedPath = item.isArchived ? item.localPath : null;
      final tempPath =
          archivedPath == null ? _tempPathFor(tempDir.path, item) : null;
      try {
        if (tempPath != null) {
          await _safStream.copyToLocalFile(item.uri, tempPath);
        }
        final source = archivedPath ?? tempPath!;
        final isImage = item.mediaType == StatusMediaType.image;
        lastSavedContentUri = isImage
            ? await _mediaSaveService.saveImage(source, album: _galAlbum)
            : await _mediaSaveService.saveVideo(source, album: _galAlbum);
        lastSavedMimeType = isImage ? 'image/*' : 'video/*';
        lastSavedName = item.name;
        succeeded++;
      } catch (_) {
        failed++;
      } finally {
        if (tempPath != null) {
          final file = File(tempPath);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
    }

    try {
      if (succeeded == 1 &&
          lastSavedContentUri != null &&
          lastSavedMimeType != null) {
        await _mediaNotificationService.notifyFileSaved(
          title: lastSavedName ?? 'Status saved',
          contentUri: lastSavedContentUri,
          mimeType: lastSavedMimeType,
        );
      } else if (succeeded > 0) {
        await _mediaNotificationService.notifySummary(
          title: 'WhatsApp',
          text: failed == 0
              ? 'Saved $succeeded to gallery'
              : 'Saved $succeeded, failed $failed',
        );
      }
    } catch (_) {}

    state = state.copyWith(
      saving: false,
      selectedUris: {},
      lastResultMessage: failed == 0
          ? StatusMessage(StatusMessageKey.whatsappSaved, count: succeeded)
          : StatusMessage(
              StatusMessageKey.whatsappSavedFailed,
              count: succeeded,
              failedCount: failed,
            ),
    );
  }

  /// Shares the selected statuses directly, independent of [saveSelected] —
  /// the file doesn't need to be saved to the gallery first (it's already
  /// local on the device, unlike a real network download).
  Future<void> shareSelected() async {
    if (state.selectedUris.isEmpty || state.busy) return;

    final toShare =
        _allItems.where((i) => state.selectedUris.contains(i.uri)).toList();
    if (toShare.isEmpty) return;
    state = state.copyWith(sharing: true, clearLastResultMessage: true);

    final tempDir = await getTemporaryDirectory();
    final tempPaths = <String>[];
    final sharePaths = <String>[];
    try {
      for (final item in toShare) {
        if (item.isArchived && item.localPath != null) {
          // Already a local file — share it directly.
          sharePaths.add(item.localPath!);
          continue;
        }
        final tempPath = _tempPathFor(tempDir.path, item);
        await _safStream.copyToLocalFile(item.uri, tempPath);
        tempPaths.add(tempPath);
        sharePaths.add(tempPath);
      }
      if (sharePaths.isNotEmpty) {
        await SharePlus.instance.share(
          ShareParams(files: sharePaths.map((p) => XFile(p)).toList()),
        );
      }
      state = state.copyWith(sharing: false, selectedUris: {});
    } catch (_) {
      state = state.copyWith(
        sharing: false,
        lastResultMessage: const StatusMessage(StatusMessageKey.couldNotShareFiles),
      );
    } finally {
      for (final path in tempPaths) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
  }

  String _tempPathFor(String dirPath, StatusItem item) {
    return '$dirPath/wa_status_${DateTime.now().microsecondsSinceEpoch}_${item.name}';
  }
}

final whatsAppStatusControllerProvider =
    StateNotifierProvider<WhatsAppStatusController, WhatsAppStatusState>(
      (ref) => WhatsAppStatusController(),
    );
