import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:model/email/attachment.dart';

class GetEmailContentLoading extends LoadingState {}

class GetEmailContentSuccess extends UIState {
  final String htmlEmailContent;
  final List<Attachment>? attachments;
  final List<Attachment>? inlineImages;
  final Email? emailCurrent;

  GetEmailContentSuccess({
    required this.htmlEmailContent,
    this.attachments,
    this.inlineImages,
    this.emailCurrent
  });

  @override
  List<Object?> get props => [
    htmlEmailContent,
    attachments,
    inlineImages,
    emailCurrent
  ];
}

class GetEmailContentFromThreadCacheSuccess extends GetEmailContentSuccess {
  /// The pictures of the inline-image placeholders of [htmlEmailContent] that had arrived, by cid, and the cids
  /// that could not be fetched.
  final Map<String, String> inlineImageSources;
  final Set<String> failedInlineImages;

  GetEmailContentFromThreadCacheSuccess({
    required super.htmlEmailContent,
    super.attachments,
    super.inlineImages,
    super.emailCurrent,
    this.inlineImageSources = const {},
    this.failedInlineImages = const {},
  });

  @override
  List<Object?> get props => [
    ...super.props,
    inlineImageSources.keys.toList(),
    failedInlineImages,
  ];
}

/// After a [GetEmailContentSuccess] whose HTML has inline-image placeholders: the picture of one of them arrived.
/// [source] is a data: URI. A success state of its own (not a failure) so that no error is shown for one image.
class GetEmailContentInlineImageSuccess extends UIState {
  final EmailId emailId;
  final String cid;
  final String source;

  GetEmailContentInlineImageSuccess({
    required this.emailId,
    required this.cid,
    required this.source,
  });

  @override
  List<Object?> get props => [emailId, cid, source];
}

/// The picture of one inline-image placeholder could not be fetched.
class GetEmailContentInlineImageFailed extends UIState {
  final EmailId emailId;
  final String cid;

  GetEmailContentInlineImageFailed({required this.emailId, required this.cid});

  @override
  List<Object?> get props => [emailId, cid];
}

class GetEmailContentFromCacheSuccess extends UIState {
  final String htmlEmailContent;
  final List<Attachment>? attachments;
  final List<Attachment>? inlineImages;
  final Email emailCurrent;

  GetEmailContentFromCacheSuccess({
    required this.htmlEmailContent,
    required this.emailCurrent,
    this.attachments,
    this.inlineImages,
  });

  @override
  List<Object?> get props => [
    htmlEmailContent,
    attachments,
    inlineImages,
    emailCurrent,
  ];
}

class LoadEmailContentCompleted extends UIState {}

class GetEmailContentFailure extends FeatureFailure {

  GetEmailContentFailure(dynamic exception, {super.onRetry})
    : super(exception: exception);
}