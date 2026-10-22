
import 'dart:convert' show HtmlEscape;

import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:core/presentation/utils/html_transformer/transform_configuration.dart';
import 'package:core/utils/app_logger.dart';
import 'package:core/utils/platform_info.dart';
import 'package:dartz/dartz.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/properties/properties.dart';
import 'package:jmap_dart_client/jmap/core/session/session.dart';
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_header_value.dart';
import 'package:jmap_dart_client/jmap/mail/email/individual_header_identifier.dart';
import 'package:model/model.dart';
import 'package:tmail_ui_user/features/email/domain/extensions/email_attachment_classifier_extension.dart';
import 'package:tmail_ui_user/features/email/domain/extensions/list_attachments_extension.dart';
import 'package:tmail_ui_user/features/email/domain/model/detailed_email.dart';
import 'package:tmail_ui_user/features/email/domain/repository/email_repository.dart';
import 'package:tmail_ui_user/features/email/domain/state/get_email_content_state.dart';

class GetEmailContentInteractor {
  final EmailRepository emailRepository;

  GetEmailContentInteractor(this.emailRepository);

  Stream<Either<Failure, Success>> execute(
    Session session,
    AccountId accountId,
    EmailId emailId,
    String baseDownloadUrl,
    TransformConfiguration transformConfiguration,
    {Properties? additionalProperties, bool showInlinePhotos = false, bool deferInlineImages = false}
  ) async* {
    try {
      yield Right<Failure, Success>(GetEmailContentLoading());

      if (PlatformInfo.isMobile) {
        yield* _getStoredOpenedEmail(
          session,
          accountId,
          emailId,
          baseDownloadUrl,
          transformConfiguration,
          additionalProperties: additionalProperties);
      } else {
        yield* _getContentEmailFromServer(
          session,
          accountId,
          emailId,
          baseDownloadUrl,
          transformConfiguration,
          additionalProperties: additionalProperties,
          showInlinePhotos: showInlinePhotos,
          deferInlineImages: deferInlineImages);
      }
    } catch (e) {
      log('GetEmailContentInteractor::execute(): exception = $e');
      yield Left<Failure, Success>(GetEmailContentFailure(
        e,
        onRetry: execute(
          session,
          accountId,
          emailId,
          baseDownloadUrl,
          transformConfiguration,
          additionalProperties: additionalProperties,
          showInlinePhotos: showInlinePhotos,
          deferInlineImages: deferInlineImages,
        ),
      ));
    }
  }

  Stream<Either<Failure, Success>> _getContentEmailFromServer(
    Session session,
    AccountId accountId,
    EmailId emailId,
    String baseDownloadUrl,
    TransformConfiguration transformConfiguration,
    {Properties? additionalProperties, bool showInlinePhotos = false, bool deferInlineImages = false}
  ) async* {
    try {
      final email = await emailRepository.getEmailContent(
        session,
        accountId,
        emailId,
        additionalProperties: additionalProperties);
      // The view shows photos that mail apps send inline without a Content-ID; the composer asks for the email as is.
      final shownEmail = showInlinePhotos ? email.withInlinePhotos() : email;
      final classified = shownEmail.toPresentationAttachments(hideDrawnInline: showInlinePhotos);
      final listAttachments = classified.attachments;
      final listInlineImages = classified.inlineImages;
      // Text first: the body is returned with a placeholder for every inline image and each picture follows as its
      // own state when it has arrived. Not for a calendar invitation (its own view shows the HTML).
      final deferImages = deferInlineImages &&
          listInlineImages.isNotEmpty &&
          listAttachments.calendarEventBlobIds.isEmpty;
      log('GetEmailContentInteractor::_getContentEmailFromServer: listAttachments = ${listAttachments.length} | listInlineImages = ${listInlineImages.length}');
      if (shownEmail.emailContentList.isNotEmpty) {
        final mapCidImageDownloadUrl = listInlineImages.toMapCidImageDownloadUrl(
          accountId: accountId,
          downloadUrl: baseDownloadUrl
        );
        final newEmailContents = await emailRepository.transformEmailContent(
          shownEmail.emailContentList,
          deferImages ? <String, String>{} : mapCidImageDownloadUrl,
          deferImages ? TransformConfiguration.forPreviewEmailOnWebWithDeferredImages() : transformConfiguration
        );
        // the downloads start now, they are reported one by one after the body
        final pictures = deferImages
            ? listInlineImages.map((image) => _loadInlineImage(
                emailId: email.id ?? emailId,
                image: image,
                downloadUrl: mapCidImageDownloadUrl[image.cid],
                transformConfiguration: transformConfiguration,
              )).toList()
            : <Future<Either<Failure, Success>>>[];

        yield Right<Failure, Success>(GetEmailContentSuccess(
          htmlEmailContent: newEmailContents.asHtmlString,
          attachments: listAttachments,
          inlineImages: listInlineImages,
          emailCurrent: email
        ));
        yield* Stream.fromFutures(pictures);
      } else {
        yield Right<Failure, Success>(GetEmailContentSuccess(
          htmlEmailContent: '',
          attachments: listAttachments,
          inlineImages: listInlineImages,
          emailCurrent: email
        ));
      }
    } catch (e) {
      logWarning('GetEmailContentInteractor::_getContentEmailFromServer():EXCEPTION: $e');
      yield Left<Failure, Success>(GetEmailContentFailure(
        e,
        onRetry: execute(
          session,
          accountId,
          emailId,
          baseDownloadUrl,
          transformConfiguration,
          additionalProperties: additionalProperties,
          showInlinePhotos: showInlinePhotos,
          deferInlineImages: deferInlineImages,
        ),
      ));
    }
  }

  /// Fetches the picture of one inline image through the same transformer as before (authenticated download, base64)
  /// and reports it as a data: URI; every problem is reported as [GetEmailContentInlineImageFailed], never thrown.
  Future<Either<Failure, Success>> _loadInlineImage({
    required EmailId emailId,
    required Attachment image,
    required String? downloadUrl,
    required TransformConfiguration transformConfiguration,
  }) async {
    final cid = image.cid;
    if (cid == null || downloadUrl == null) {
      return Right<Failure, Success>(GetEmailContentInlineImageFailed(emailId: emailId, cid: cid ?? ''));
    }
    try {
      // the type the data: URI is labelled with is one a browser draws, else jpeg as before
      final mimeType = _drawnImageTypes.contains(image.type?.mimeType) ? image.type!.mimeType : 'image/jpeg';
      final transformed = await emailRepository.transformEmailContent(
        [EmailContent(EmailContentType.textHtml, '<img src="cid:${const HtmlEscape().convert(cid)}" data-mimetype="$mimeType">')],
        {cid: downloadUrl},
        transformConfiguration,
      );
      final source = _sourceOfFirstImage(transformed.asHtmlString);
      if (source != null && source.startsWith('data:image/')) {
        return Right<Failure, Success>(
          GetEmailContentInlineImageSuccess(emailId: emailId, cid: cid, source: source),
        );
      }
    } catch (e) {
      logWarning('GetEmailContentInteractor::_loadInlineImage():EXCEPTION: $e');
    }
    return Right<Failure, Success>(GetEmailContentInlineImageFailed(emailId: emailId, cid: cid));
  }

  static const _drawnImageTypes = {'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp'};

  /// The src of the first <img> in [html], cut out of the string. The picture is a base64 data: URI of megabytes; parsing
  /// the HTML again just to read one attribute took about 400 ms of the page's main thread for a 4.6 MB photo (measured
  /// with dart2js), a visible freeze right after the text was shown. The serializer writes the attribute as src="..." and
  /// escapes any quote in a value, and the markup here is our own single <img>, so the first quote after it ends the value.
  static String? _sourceOfFirstImage(String html) {
    const marker = '<img src="';
    final start = html.indexOf(marker);
    if (start < 0) return null;
    final from = start + marker.length;
    final end = html.indexOf('"', from);
    return end < 0 ? null : html.substring(from, end);
  }

  Stream<Either<Failure, Success>> _getStoredOpenedEmail(
    Session session,
    AccountId accountId,
    EmailId emailId,
    String baseDownloadUrl,
    TransformConfiguration transformConfiguration,
    {Properties? additionalProperties}
  ) async* {
    try {
      final tupleEmail = await Future.wait([
        emailRepository.getStoredEmail(session, accountId, emailId),
        emailRepository.getStoredOpenedEmail(session, accountId, emailId),
      ], eagerError: true);
      final emailCache = tupleEmail[0] as Email;
      final detailedEmail = tupleEmail[1] as DetailedEmail;
      log('GetEmailContentInteractor::_getStoredOpenedEmail: attachments = ${detailedEmail.attachments?.length} | inlineImages = ${detailedEmail.inlineImages?.length}');
      yield Right<Failure, Success>(GetEmailContentFromCacheSuccess(
        htmlEmailContent: detailedEmail.htmlEmailContent ?? '',
        attachments: detailedEmail.attachments ?? [],
        inlineImages: detailedEmail.inlineImages ?? [],
        emailCurrent: emailCache.copyWith(
          headers: detailedEmail.headers,
          individualHeaders: () {
            final map = emailCache.individualHeaders.merge({
              if (detailedEmail.sMimeStatusHeader != null)
                IndividualHeaderIdentifier.sMimeStatusHeader: detailedEmail.sMimeStatusHeader!,
            });
            return map.isEmpty ? null : map;
          }(),
          references: detailedEmail.references,
          messageId: detailedEmail.messageId,
        )
      ));
    } catch (e) {
      logWarning('GetEmailContentInteractor::_getStoredOpenedEmail():EXCEPTION: $e');
      yield* _getStoredNewEmail(
        session,
        accountId,
        emailId,
        baseDownloadUrl,
        transformConfiguration,
        additionalProperties: additionalProperties
      );
    }
  }

  Stream<Either<Failure, Success>> _getStoredNewEmail(
    Session session,
    AccountId accountId,
    EmailId emailId,
    String baseDownloadUrl,
    TransformConfiguration transformConfiguration,
    {Properties? additionalProperties}
  ) async* {
    try {
      final tupleEmail = await Future.wait([
        emailRepository.getStoredEmail(session, accountId, emailId),
        emailRepository.getStoredNewEmail(session, accountId, emailId),
      ], eagerError: true);
      final emailCache = tupleEmail[0] as Email;
      final detailedEmail = tupleEmail[1] as DetailedEmail;
      log('GetEmailContentInteractor::_getStoredNewEmail: attachments = ${detailedEmail.attachments?.length} | inlineImages = ${detailedEmail.inlineImages?.length}');
      yield Right<Failure, Success>(GetEmailContentFromCacheSuccess(
        htmlEmailContent: detailedEmail.htmlEmailContent ?? '',
        attachments: detailedEmail.attachments ?? [],
        inlineImages: detailedEmail.inlineImages ?? [],
        emailCurrent: emailCache.copyWith(
          headers: detailedEmail.headers,
          individualHeaders: () {
            final map = emailCache.individualHeaders.merge({
              if (detailedEmail.sMimeStatusHeader != null)
                IndividualHeaderIdentifier.sMimeStatusHeader: detailedEmail.sMimeStatusHeader!,
              if (detailedEmail.identityHeader != null)
                IndividualHeaderIdentifier.identityHeader: detailedEmail.identityHeader!,
            });
            return map.isEmpty ? null : map;
          }(),
          references: detailedEmail.references,
          messageId: detailedEmail.messageId,
        )
      ));
    } catch (e) {
      logWarning('GetEmailContentInteractor::_getStoredNewEmail():EXCEPTION: $e');
      yield* _getContentEmailFromServer(
        session,
        accountId,
        emailId,
        baseDownloadUrl,
        transformConfiguration,
        additionalProperties: additionalProperties
      );
    }
  }
}

extension on Map<IndividualHeaderIdentifier, EmailHeaderValue> {
  Map<IndividualHeaderIdentifier, EmailHeaderValue> merge(
    Map<IndividualHeaderIdentifier, EmailHeaderValue> other,
  ) {
    return Map.from(this)..addAll(other);
  }
}
