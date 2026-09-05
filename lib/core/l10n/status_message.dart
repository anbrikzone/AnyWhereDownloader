import '../../l10n/app_localizations.dart';

/// Identifies one of the small set of status/result messages a controller
/// (`YouTubeController`, `TikTokController`, `XTwitterController`,
/// `InstagramController`, `WhatsAppStatusController`, `LibraryController`)
/// can set on its state. Controllers are plain `StateNotifier`s with no
/// `BuildContext`, so they can't call `AppLocalizations.of(context)`
/// directly — they set one of these instead, and the screen (which has a
/// `BuildContext` in its `ref.listen` callback) resolves it to localized
/// text via [resolveStatusMessage].
enum StatusMessageKey {
  /// Pass-through for an already-formatted string that isn't localized yet
  /// — currently only `ExtractionException.message` (thrown by
  /// `youtube_extractor.dart`/`tiktok_extractor.dart`/
  /// `x_twitter_extractor.dart`/`instagram_extractor.dart` when no
  /// downloadable format is found). A known, documented gap (see
  /// CLAUDE.md's "Multi-language support" section) rather than a silent
  /// one — these are rare edge-case messages, not the common path.
  raw,
  downloadAlreadyInProgress,
  notYoutubeLink,
  notTiktokLink,
  notXTwitterLink,
  notInstagramLink,
  notLinkedInLink,
  couldNotFetchVideo,
  couldNotFetchPost,
  saved,
  downloadCanceled,
  downloadFailed,
  couldNotShareFiles,
  whatsappSaved,
  whatsappSavedFailed,
  deletedCount,
  deleteFailed,
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
    this.rawText,
  });

  /// Convenience constructor for [StatusMessageKey.raw].
  const StatusMessage.raw(String text) : this(StatusMessageKey.raw, rawText: text);

  final StatusMessageKey key;
  final String? error;
  final int? count;
  final int? failedCount;
  final String? rawText;

  @override
  bool operator ==(Object other) =>
      other is StatusMessage &&
      other.key == key &&
      other.error == error &&
      other.count == count &&
      other.failedCount == failedCount &&
      other.rawText == rawText;

  @override
  int get hashCode => Object.hash(key, error, count, failedCount, rawText);
}

String resolveStatusMessage(AppLocalizations l10n, StatusMessage message) {
  switch (message.key) {
    case StatusMessageKey.raw:
      return message.rawText ?? '';
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
    case StatusMessageKey.deletedCount:
      return l10n.deletedCount(message.count ?? 0);
    case StatusMessageKey.deleteFailed:
      return l10n.deleteFailed(message.error ?? '');
  }
}
