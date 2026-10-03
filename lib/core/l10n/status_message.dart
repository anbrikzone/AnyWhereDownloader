import '../../l10n/app_localizations.dart';
import '../extraction/media_extractor.dart';

/// Identifies one of the small set of status/result messages a controller
/// (`YouTubeController`, `DirectDownloadController` for TikTok/X/Instagram/
/// LinkedIn, `WhatsAppStatusController`, `LibraryController`)
/// can set on its state. Controllers are plain `StateNotifier`s with no
/// `BuildContext`, so they can't call `AppLocalizations.of(context)`
/// directly — they set one of these instead, and the screen (which has a
/// `BuildContext` in its `ref.listen` callback) resolves it to localized
/// text via [resolveStatusMessage].
enum StatusMessageKey {
  /// An extractor's own [ExtractionException] — localized from its
  /// [StatusMessage.extractionCode], with [StatusMessage.error] holding the
  /// untranslated detail (if any).
  extractionFailed,
  downloadAlreadyInProgress,
  notYoutubeLink,
  notTiktokLink,
  notXTwitterLink,
  notInstagramLink,
  notLinkedInLink,
  couldNotFetchVideo,
  couldNotFetchPost,
  couldNotFetchPlaylist,
  saved,
  downloadCanceled,
  downloadFailed,
  couldNotShareFiles,
  whatsappSaved,
  whatsappSavedFailed,
  statusesArchived,
  playlistSaved,
  deletedCount,
  deleteFailed,
  migrationIncomplete,
  migrationPostponed,
}

/// A [StatusMessageKey] plus whatever interpolation data it needs (e.g. an
/// error string, a count) — never more than the one or two fields each key
/// actually uses.
class StatusMessage {
  const StatusMessage(
    this.key, {
    this.error,
    this.count,
    this.failedCount,
    this.extractionCode,
  });

  /// Convenience constructor for [StatusMessageKey.extractionFailed].
  StatusMessage.extraction(ExtractionException e)
      : this(
          StatusMessageKey.extractionFailed,
          extractionCode: e.code,
          error: e.detail,
        );

  final StatusMessageKey key;
  final String? error;
  final int? count;
  final int? failedCount;
  final ExtractionErrorCode? extractionCode;

  @override
  bool operator ==(Object other) =>
      other is StatusMessage &&
      other.key == key &&
      other.error == error &&
      other.count == count &&
      other.failedCount == failedCount &&
      other.extractionCode == extractionCode;

  @override
  int get hashCode => Object.hash(key, error, count, failedCount, extractionCode);
}

String resolveStatusMessage(AppLocalizations l10n, StatusMessage message) {
  switch (message.key) {
    case StatusMessageKey.extractionFailed:
      final text = _extractionText(l10n, message.extractionCode);
      final detail = message.error;
      return detail == null || detail.isEmpty ? text : '$text ($detail)';
    case StatusMessageKey.downloadAlreadyInProgress:
      return l10n.downloadAlreadyInProgress;
    case StatusMessageKey.notYoutubeLink:
      return l10n.notYoutubeLink;
    case StatusMessageKey.notTiktokLink:
      return l10n.notTiktokLink;
    case StatusMessageKey.notXTwitterLink:
      return l10n.notXTwitterLink;
    case StatusMessageKey.notInstagramLink:
      return l10n.notInstagramLink;
    case StatusMessageKey.notLinkedInLink:
      return l10n.notLinkedinLink;
    case StatusMessageKey.couldNotFetchVideo:
      return l10n.couldNotFetchVideo(message.error ?? '');
    case StatusMessageKey.couldNotFetchPost:
      return l10n.couldNotFetchPost(message.error ?? '');
    case StatusMessageKey.couldNotFetchPlaylist:
      return l10n.couldNotFetchPlaylist(message.error ?? '');
    case StatusMessageKey.saved:
      return l10n.savedMessage;
    case StatusMessageKey.downloadCanceled:
      return l10n.downloadCanceledMessage;
    case StatusMessageKey.downloadFailed:
      return l10n.downloadFailedMessage(message.error ?? '');
    case StatusMessageKey.couldNotShareFiles:
      return l10n.couldNotShareFiles;
    case StatusMessageKey.whatsappSaved:
      return l10n.whatsappSavedCount(message.count ?? 0);
    case StatusMessageKey.whatsappSavedFailed:
      return l10n.whatsappSavedFailedCount(
        message.count ?? 0,
        message.failedCount ?? 0,
      );
    case StatusMessageKey.statusesArchived:
      return l10n.statusesArchivedCount(message.count ?? 0);
    case StatusMessageKey.playlistSaved:
      return l10n.playlistSavedResult(
        message.count ?? 0,
        message.failedCount ?? 0,
      );
    case StatusMessageKey.deletedCount:
      return l10n.deletedCount(message.count ?? 0);
    case StatusMessageKey.deleteFailed:
      return l10n.deleteFailed(message.error ?? '');
    case StatusMessageKey.migrationIncomplete:
      return l10n.migrationIncomplete;
    case StatusMessageKey.migrationPostponed:
      return l10n.migrationPostponed;
  }
}

String _extractionText(AppLocalizations l10n, ExtractionErrorCode? code) {
  switch (code) {
    case ExtractionErrorCode.noDownloadableMedia:
    case null:
      return l10n.extractionNoDownloadableMedia;
    case ExtractionErrorCode.lookupUnreachable:
      return l10n.extractionLookupUnreachable;
    case ExtractionErrorCode.lookupHttpError:
      return l10n.extractionLookupHttpError;
    case ExtractionErrorCode.lookupBadResponse:
      return l10n.extractionLookupBadResponse;
    case ExtractionErrorCode.notResolved:
      return l10n.extractionNotResolved;
  }
}
