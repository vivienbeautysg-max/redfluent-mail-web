import 'dart:io';

import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:core/presentation/utils/html_transformer/transform_configuration.dart';
import 'package:core/utils/platform_info.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_body_part.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_body_value.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:model/email/email_content.dart';
import 'package:model/extensions/email_extension.dart';
import 'package:model/extensions/list_email_content_extension.dart';
import 'package:tmail_ui_user/features/email/domain/extensions/email_attachment_classifier_extension.dart';
import 'package:tmail_ui_user/features/email/domain/repository/email_repository.dart';
import 'package:tmail_ui_user/features/email/domain/state/get_email_content_state.dart';
import 'package:tmail_ui_user/features/email/domain/usecases/get_email_content_interactor.dart';

import '../../../../fixtures/account_fixtures.dart';
import '../../../../fixtures/mime_fixtures.dart';
import '../../../../fixtures/session_fixtures.dart';

import 'get_email_content_interactor_test.mocks.dart';

@GenerateNiceMocks([MockSpec<EmailRepository>()])
void main() {
  late MockEmailRepository mockEmailRepository;
  late GetEmailContentInteractor interactor;

  final session = SessionFixtures.aliceSession;
  final accountId = AccountFixtures.aliceAccountId;
  final emailId = EmailId(Id('test-email-id'));
  const baseDownloadUrl = 'https://download.example.com/';
  final transformConfig = TransformConfiguration.forPreviewEmailOnWeb();

  setUp(() {
    mockEmailRepository = MockEmailRepository();
    interactor = GetEmailContentInteractor(mockEmailRepository);
  });

  // Helper: build EmailBodyPart for a regular (external) attachment
  EmailBodyPart makeExternalAttachment({required String blobIdValue, String? name}) =>
      EmailBodyPart(blobId: Id(blobIdValue), disposition: 'attachment', name: name);

  // Helper: build EmailBodyPart for an inline attachment with a cid
  EmailBodyPart makeInlineAttachment({required String blobIdValue, required String cid}) =>
      EmailBodyPart(blobId: Id(blobIdValue), cid: cid, disposition: 'inline');

  // Helper: build an Email with given attachments and an optional HTML body string
  Email makeEmail({Set<EmailBodyPart>? attachments, String htmlContent = ''}) {
    if (htmlContent.isEmpty) {
      return Email(id: emailId, attachments: attachments);
    }
    return Email(
      id: emailId,
      attachments: attachments,
      htmlBody: {
        EmailBodyPart(partId: PartId('1'), type: MediaType('text', 'html')),
      },
      bodyValues: {
        PartId('1'): EmailBodyValue(
          value: htmlContent,
          isEncodingProblem: false,
          isTruncated: false,
        ),
      },
    );
  }

  // Helper: stub transformEmailContent so the stream can proceed past email content processing
  void stubTransform() {
    when(mockEmailRepository.transformEmailContent(any, any, any))
        .thenAnswer((_) async => []);
  }

  // Helper: extract GetEmailContentSuccess from stream results
  Future<GetEmailContentSuccess> runAndGetSuccess() async {
    final results = await interactor
        .execute(session, accountId, emailId, baseDownloadUrl, transformConfig)
        .toList();
    return results
        .whereType<Right<Failure, Success>>()
        .map((r) => r.value)
        .whereType<GetEmailContentSuccess>()
        .first;
  }

  // Helper: stub + run a single inline-attachment scenario and return the success state
  Future<GetEmailContentSuccess> runWithInlinePart({
    required String cid,
    required String blobIdValue,
    required String htmlContent,
  }) async {
    final inlinePart = makeInlineAttachment(blobIdValue: blobIdValue, cid: cid);
    when(mockEmailRepository.getEmailContent(session, accountId, emailId))
        .thenAnswer((_) async => makeEmail(attachments: {inlinePart}, htmlContent: htmlContent));
    stubTransform();
    return runAndGetSuccess();
  }

  group('GetEmailContentInteractor::classifyAttachments::', () {
    test('no attachments: both lists are empty', () async {
      final email = makeEmail();
      when(mockEmailRepository.getEmailContent(session, accountId, emailId))
          .thenAnswer((_) async => email);
      stubTransform();

      final success = await runAndGetSuccess();

      expect(success.attachments, isEmpty);
      expect(success.inlineImages, isEmpty);
    });

    test('external attachment only: appears in attachments, not inlineImages', () async {
      final extPart = makeExternalAttachment(blobIdValue: 'blob-ext', name: 'doc.pdf');
      when(mockEmailRepository.getEmailContent(session, accountId, emailId))
          .thenAnswer((_) async => makeEmail(attachments: {extPart}));
      stubTransform();

      final success = await runAndGetSuccess();

      expect(success.attachments, hasLength(1));
      expect(success.attachments!.first.blobId, equals(Id('blob-ext')));
      expect(success.inlineImages, isEmpty);
    });

    for (final tc in [
      (
        description: 'referenced inline image: appears in inlineImages, not attachments',
        cid: 'referenced-cid@domain',
        blobId: 'blob-inline',
        expectInline: true,
      ),
      (
        description: 'orphaned inline image: promoted to attachments, not inlineImages',
        cid: 'orphan-cid@domain',
        blobId: 'blob-orphan',
        expectInline: false,
      ),
    ]) {
      final htmlContent = tc.expectInline
          ? '<img src="cid:${tc.cid}">'
          : '<p>No cid reference here</p>';

      test(tc.description, () async {
        final success = await runWithInlinePart(
          cid: tc.cid,
          blobIdValue: tc.blobId,
          htmlContent: htmlContent,
        );
        final populated = tc.expectInline ? success.inlineImages : success.attachments;
        final empty = tc.expectInline ? success.attachments : success.inlineImages;
        expect(populated, hasLength(1));
        expect(populated!.first.cid, equals(tc.cid));
        expect(empty, isEmpty);
      });
    }

    test('empty html body: inline image with cid treated as orphaned', () async {
      const cid = 'some-cid@domain';
      final inlinePart = makeInlineAttachment(blobIdValue: 'blob-inline', cid: cid);
      // No htmlContent → emailContentList is empty → _extractReferencedCids returns {}
      when(mockEmailRepository.getEmailContent(session, accountId, emailId))
          .thenAnswer((_) async => makeEmail(attachments: {inlinePart}));
      stubTransform();

      final success = await runAndGetSuccess();

      expect(success.attachments, hasLength(1));
      expect(success.inlineImages, isEmpty);
    });

    test('mixed: external + referenced + orphaned are correctly partitioned', () async {
      const referencedCid = 'referenced@domain';
      const orphanedCid = 'orphan@domain';
      final extPart = makeExternalAttachment(blobIdValue: 'blob-ext', name: 'report.pdf');
      final referencedPart = makeInlineAttachment(blobIdValue: 'blob-ref', cid: referencedCid);
      final orphanedPart = makeInlineAttachment(blobIdValue: 'blob-orphan', cid: orphanedCid);
      when(mockEmailRepository.getEmailContent(session, accountId, emailId))
          .thenAnswer((_) async => makeEmail(
            attachments: {extPart, referencedPart, orphanedPart},
            htmlContent: '<img src="cid:$referencedCid">',
          ));
      stubTransform();

      final success = await runAndGetSuccess();

      // attachments = external + orphaned (2 items)
      expect(success.attachments, hasLength(2));
      final attachmentBlobIds = success.attachments!.map((a) => a.blobId).toSet();
      expect(attachmentBlobIds, containsAll([Id('blob-ext'), Id('blob-orphan')]));

      // inlineImages = referenced only (1 item)
      expect(success.inlineImages, hasLength(1));
      expect(success.inlineImages!.first.cid, equals(referencedCid));
    });
  });

  group('GetEmailContentInteractor::showInlinePhotos:: (rf12)::', () {
    // flutter test runs as Android, where the interactor reads the mobile cache first; the web build reads the server.
    setUp(() => PlatformInfo.isTestingForWeb = true);
    tearDown(() => PlatformInfo.isTestingForWeb = false);

    const downloadUrl = 'https://download.example.com/download/{accountId}/{blobId}/{name}';

    void stubFetched(Email email) {
      when(mockEmailRepository.getEmailContent(session, accountId, emailId))
          .thenAnswer((_) async => email);
      stubTransform();
    }

    // [showInlinePhotos] null: the argument is left out, as the composer's calls do.
    Future<GetEmailContentSuccess> run(Email fetched, {bool? showInlinePhotos}) async {
      stubFetched(fetched);
      final results = await (showInlinePhotos == null
              ? interactor.execute(session, accountId, emailId, downloadUrl, transformConfig)
              : interactor.execute(session, accountId, emailId, downloadUrl, transformConfig,
                  showInlinePhotos: showInlinePhotos))
          .toList();
      return results
          .whereType<Right<Failure, Success>>()
          .map((r) => r.value)
          .whereType<GetEmailContentSuccess>()
          .first;
    }

    // What transformEmailContent was given: the contents to turn into HTML and the cid -> download URL map.
    ({List<EmailContent> contents, Map<String, String> cidUrls}) transformArguments() {
      final captured = verify(mockEmailRepository.transformEmailContent(captureAny, captureAny, any)).captured;
      return (contents: captured[0] as List<EmailContent>, cidUrls: captured[1] as Map<String, String>);
    }

    test('the composer does not ask: layouts 1, 7 and 12 give what the email as fetched gives (as in rf11)', () async {
      for (final key in ['apple_ios_photo', 'attachment_photo', 'gmail_inline']) {
        clearInteractions(mockEmailRepository);
        final fetched = loadMimeFixture(key);
        final success = await run(fetched);

        final old = fetched.toPresentationAttachments();
        expect(success.attachments, old.attachments, reason: key);
        expect(success.inlineImages, old.inlineImages, reason: key);
        expect(transformArguments().contents, fetched.emailContentList, reason: key);
        expect(success.inlineImages?.where((a) => a.cid?.startsWith('rf-photo-') ?? false), isEmpty, reason: key);
      }
    });

    test('the email view asks: layout 1 shows the photo in the body and registers it as an inline image', () async {
      final fetched = loadMimeFixture('apple_ios_photo');
      final photo = fetched.attachments!.single;
      final success = await run(fetched, showInlinePhotos: true);

      final cid = 'rf-photo-4-${photo.blobId!.value}';
      expect(success.inlineImages!.map((a) => a.cid), [cid]);
      expect(success.attachments, isEmpty);
      final args = transformArguments();
      expect(args.contents.asHtmlString, contains('<img src="cid:$cid"'));
      expect(args.cidUrls.keys, [cid]);
      expect(args.cidUrls[cid], startsWith('https://download.example.com/download/'));
      expect(args.cidUrls[cid], contains(photo.blobId!.value));
    });

    test('the email view asks: layout 4 (HEIC) is an attachment, not an inline image', () async {
      final success = await run(loadMimeFixture('apple_heic'), showInlinePhotos: true);

      expect(success.inlineImages, isEmpty);
      expect(success.attachments!.map((a) => a.name), ['IMG_0002.HEIC']);
      expect(transformArguments().cidUrls, isEmpty);
    });

    test('the email view asks: emailCurrent is the email as fetched', () async {
      final fetched = loadMimeFixture('apple_ios_photo');
      stubFetched(fetched);
      final results = await interactor
          .execute(session, accountId, emailId, downloadUrl, transformConfig, showInlinePhotos: true)
          .toList();
      final success = results.whereType<Right<Failure, Success>>().map((r) => r.value).whereType<GetEmailContentSuccess>().first;

      expect(identical(success.emailCurrent, fetched), isTrue);
    });

    test('the email view asks: layouts other than 1-5 give exactly what they give without it', () async {
      for (final key in mimeUnchangedLayouts) {
        final fetched = loadMimeFixture(key);
        clearInteractions(mockEmailRepository);
        final plain = await run(fetched);
        final plainArgs = transformArguments();
        clearInteractions(mockEmailRepository);
        final asked = await run(fetched, showInlinePhotos: true);
        final askedArgs = transformArguments();

        expect(asked.attachments, plain.attachments, reason: key);
        expect(asked.inlineImages, plain.inlineImages, reason: key);
        expect(askedArgs.contents, plainArgs.contents, reason: key);
        expect(askedArgs.cidUrls, plainArgs.cidUrls, reason: key);
      }
    });

    test('a retry after a failure keeps the request for the photos', () async {
      final fetched = loadMimeFixture('apple_ios_photo');
      var calls = 0;
      when(mockEmailRepository.getEmailContent(session, accountId, emailId)).thenAnswer((_) async {
        if (calls++ == 0) throw Exception('network');
        return fetched;
      });
      stubTransform();

      final first = await interactor
          .execute(session, accountId, emailId, downloadUrl, transformConfig, showInlinePhotos: true)
          .toList();
      final failure = first.whereType<Left<Failure, Success>>().map((l) => l.value).whereType<GetEmailContentFailure>().single;
      final retried = await failure.onRetry!.toList();
      final success = retried.whereType<Right<Failure, Success>>().map((r) => r.value).whereType<GetEmailContentSuccess>().single;

      expect(success.inlineImages, hasLength(1));
      expect(success.attachments, isEmpty);
    });

    test('only the email view and the thread action reactor ask (the .eml preview always shows photos); the composer never does', () {
      final askers = {
        for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
          f.path.replaceAll(Platform.pathSeparator, '/'): 'showInlinePhotos: true'.allMatches(f.readAsStringSync()).length,
      }..removeWhere((_, count) => count == 0);

      expect(askers, {
        // the call that loads the opened email and its retry
        'lib/features/email/presentation/controller/single_email_controller.dart': 2,
        'lib/features/email/presentation/utils/email_action_reactor/email_action_reactor.dart': 1,
      });
      expect(
        File('lib/features/email/data/datasource_impl/email_datasource_impl.dart').readAsStringSync(),
        contains('previewEmailEMLRequest.email.withInlinePhotos()'),
      );
      for (final composerFile in Directory('lib/features/composer')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final source = composerFile.readAsStringSync();
        expect(source.contains('showInlinePhotos'), isFalse, reason: composerFile.path);
        expect(source.contains('withInlinePhotos'), isFalse, reason: composerFile.path);
      }
    });
  });
}
