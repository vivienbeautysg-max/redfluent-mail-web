import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/utils/html_transformer/transform_configuration.dart';
import 'package:core/utils/file_utils.dart';
import 'package:core/utils/preview_eml_file_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:html/parser.dart';
import 'package:http_parser/http_parser.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/core/unsigned_int.dart';
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_address.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_body_part.dart';
import 'package:model/email/email_content.dart';
import 'package:tmail_ui_user/features/email/data/datasource_impl/email_datasource_impl.dart';
import 'package:tmail_ui_user/features/email/data/local/html_analyzer.dart';
import 'package:tmail_ui_user/features/email/data/network/email_api.dart';
import 'package:tmail_ui_user/features/email/domain/model/preview_email_eml_request.dart';
import 'package:tmail_ui_user/main/exceptions/thrower/exception_thrower.dart';
import 'package:tmail_ui_user/main/exceptions/thrower/send_email_exception_thrower.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';

import '../../../../fixtures/account_fixtures.dart';
import '../../../../fixtures/mime_fixtures.dart';
import '../../../../fixtures/session_fixtures.dart';

class _FakeFileUtils extends Fake implements FileUtils {
  @override
  Future<String> convertImageAssetToBase64(String assetImage) async => '';
}

class _FakeHtmlAnalyzer extends Fake implements HtmlAnalyzer {}

class _FakeEmailAPI extends Fake implements EmailAPI {}

/// Hands the HTML back as it is and keeps the cid -> download URL map it was given (the real one fetches the images).
class _PassThroughHtmlAnalyzer extends Fake implements HtmlAnalyzer {
  final cidUrls = <Map<String, String>>[];

  @override
  Future<EmailContent> transformEmailContent(
    EmailContent emailContent,
    Map<String, String> mapCidImageDownloadUrl,
    TransformConfiguration transformConfiguration,
  ) async {
    cidUrls.add(mapCidImageDownloadUrl);
    return emailContent;
  }
}

class _FakeExceptionThrower extends Fake implements ExceptionThrower {}

void main() {
  setUp(() {
    Get.put<SendEmailExceptionThrower>(SendEmailExceptionThrower());
    Get.put<PreviewEmlFileUtils>(PreviewEmlFileUtils());
    Get.put<HtmlAnalyzer>(_FakeHtmlAnalyzer());
    Get.put<FileUtils>(_FakeFileUtils());
    Get.put<ImagePaths>(ImagePaths());
  });

  tearDown(Get.reset);

  group('EmailDataSourceImpl.generatePreviewEmailEMLContent', () {
    test('SHOULD show the subject, sender name and attachment name exactly once escaped', () async {
      const subject = 'Q&A <b>today</b>';
      const senderName = 'Bob <Admin> & Co';
      const attachmentName = 'a<b>&c.pdf';
      final appLocalizations = AppLocalizations();
      final dataSource = EmailDataSourceImpl(_FakeEmailAPI(), _FakeExceptionThrower());

      final html = await dataSource.generatePreviewEmailEMLContent(PreviewEmailEMLRequest(
        accountId: AccountFixtures.aliceAccountId,
        session: SessionFixtures.aliceSession,
        ownEmailAddress: 'alice@example.com',
        blobId: Id('emlBlobId'),
        email: Email(
          id: EmailId(Id('emailId')),
          subject: subject,
          from: {EmailAddress(senderName, 'bob@example.com')},
          attachments: {
            EmailBodyPart(
              partId: PartId('2'),
              blobId: Id('blobId'),
              name: attachmentName,
              size: UnsignedInt(1024),
              type: MediaType.parse('application/pdf'),
              disposition: 'attachment',
            ),
          },
        ),
        locale: const Locale('en'),
        appLocalizations: appLocalizations,
        baseDownloadUrl: 'https://jmap.example.com/download/{accountId}/{blobId}/?type={type}&name={name}',
      ));

      final document = parse(html);
      expect(document.querySelector('.email-subject')!.text, '${appLocalizations.subject}: $subject');
      expect(document.querySelector('.sender')!.text.trim(), '$senderName <bob@example.com>');
      expect(document.querySelector('.file-name')!.text, attachmentName);
    });

    test('SHOULD strip bidi overrides from the attachment name', () async {
      const subject = 'Q&A <b>today</b>';
      const senderName = 'Bob <Admin> & Co';
      const attachmentName = 'invoice\u202Efdp.exe';
      final appLocalizations = AppLocalizations();
      final dataSource = EmailDataSourceImpl(_FakeEmailAPI(), _FakeExceptionThrower());

      final html = await dataSource.generatePreviewEmailEMLContent(PreviewEmailEMLRequest(
        accountId: AccountFixtures.aliceAccountId,
        session: SessionFixtures.aliceSession,
        ownEmailAddress: 'alice@example.com',
        blobId: Id('emlBlobId'),
        email: Email(
          id: EmailId(Id('emailId')),
          subject: subject,
          from: {EmailAddress(senderName, 'bob@example.com')},
          attachments: {
            EmailBodyPart(
              partId: PartId('2'),
              blobId: Id('blobId'),
              name: attachmentName,
              size: UnsignedInt(1024),
              type: MediaType.parse('application/pdf'),
              disposition: 'attachment',
            ),
          },
        ),
        locale: const Locale('en'),
        appLocalizations: appLocalizations,
        baseDownloadUrl: 'https://jmap.example.com/download/{accountId}/{blobId}/?type={type}&name={name}',
      ));

      final document = parse(html);
      expect(document.querySelector('.file-name')!.text, 'invoicefdp.exe');
    });

    // rf12: a forwarded message (.eml) from Apple Mail shows its photo like the open email does
    PreviewEmailEMLRequest requestFor(Email email) => PreviewEmailEMLRequest(
          accountId: AccountFixtures.aliceAccountId,
          session: SessionFixtures.aliceSession,
          ownEmailAddress: 'alice@example.com',
          blobId: Id('emlBlobId'),
          email: email,
          locale: const Locale('en'),
          appLocalizations: AppLocalizations(),
          baseDownloadUrl: 'https://jmap.example.com/download/{accountId}/{blobId}/?type={type}&name={name}',
        );

    test('SHOULD show a photo that Apple Mail sends without Content-ID in the body, not in the attachment list', () async {
      final analyzer = _PassThroughHtmlAnalyzer();
      Get.replace<HtmlAnalyzer>(analyzer);
      final fetched = loadMimeFixture('apple_ios_photo');
      final cid = 'rf-photo-4-${fetched.attachments!.single.blobId!.value}';
      final dataSource = EmailDataSourceImpl(_FakeEmailAPI(), _FakeExceptionThrower());

      final html = await dataSource.generatePreviewEmailEMLContent(requestFor(fetched));

      final document = parse(html);
      expect(document.querySelectorAll('img[src="cid:$cid"]'), hasLength(1));
      // the analyzer is called once per piece of the body, each time with the same map
      expect(analyzer.cidUrls.expand((map) => map.keys).toSet(), {cid});
      expect(document.querySelectorAll('.file-name'), isEmpty);
    });

    test('SHOULD list a HEIC photo as an attachment, not as a broken image', () async {
      final analyzer = _PassThroughHtmlAnalyzer();
      Get.replace<HtmlAnalyzer>(analyzer);
      final dataSource = EmailDataSourceImpl(_FakeEmailAPI(), _FakeExceptionThrower());

      final html = await dataSource.generatePreviewEmailEMLContent(requestFor(loadMimeFixture('apple_heic')));

      final document = parse(html);
      expect(document.querySelectorAll('img[src^="cid:"]'), isEmpty);
      expect(document.querySelector('.file-name')!.text, 'IMG_0002.HEIC');
    });
  });
}
