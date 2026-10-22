import 'dart:async';
import 'dart:convert' show HtmlEscape;
import 'dart:io';
import 'dart:typed_data';

import 'package:core/data/network/dio_client.dart';
import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:core/presentation/utils/html_transformer/transform_configuration.dart';
import 'package:core/presentation/utils/html_transformer/html_transform.dart';
import 'package:core/utils/platform_info.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart' show CancelToken, Options, ProgressCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' show parse;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_body_part.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_body_value.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:model/email/email_content.dart';
import 'package:tmail_ui_user/features/email/data/local/html_analyzer.dart';
import 'package:tmail_ui_user/features/email/domain/repository/email_repository.dart';
import 'package:tmail_ui_user/features/email/domain/state/get_email_content_state.dart';
import 'package:tmail_ui_user/features/email/domain/usecases/get_email_content_interactor.dart';
import 'package:tmail_ui_user/features/upload/data/network/file_uploader.dart';
import 'package:uuid/uuid.dart';

import '../../../../fixtures/account_fixtures.dart';
import '../../../../fixtures/mime_fixtures.dart';
import '../../../../fixtures/session_fixtures.dart';

import 'get_email_content_interactor_deferred_images_test.mocks.dart';

/// The download client of the transformer: every picture is answered when the test says so (or at once when no
/// answer was prepared); the URLs it was asked for are kept.
class _PictureDioClient extends Fake implements DioClient {
  final requested = <String>[];
  final _answers = <String, Completer<Uint8List>>{};

  Completer<Uint8List> answerFor(String blobId) => _answers.putIfAbsent(blobId, Completer.new);

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    requested.add(path);
    for (final entry in _answers.entries) {
      if (path.contains(entry.key)) return entry.value.future;
    }
    return Future.value(Uint8List.fromList([137, 80, 78, 71]));
  }
}

class _FakeFileUploader extends Fake implements FileUploader {}

@GenerateNiceMocks([MockSpec<EmailRepository>()])
void main() {
  late MockEmailRepository repository;
  late GetEmailContentInteractor interactor;
  late _PictureDioClient dio;

  final session = SessionFixtures.aliceSession;
  final accountId = AccountFixtures.aliceAccountId;
  final emailId = EmailId(Id('test-email-id'));
  const downloadUrl = 'https://download.example.com/download/{accountId}/{blobId}/{name}';

  setUp(() {
    PlatformInfo.isTestingForWeb = true;    // flutter test runs as Android, the web build reads the server
    dio = _PictureDioClient();
    repository = MockEmailRepository();
    interactor = GetEmailContentInteractor(repository);
    // the real transformer chain (sanitizer, DOM transformers, authenticated download) behind a fake download client
    final analyzer = HtmlAnalyzer(HtmlTransform(dio, const HtmlEscape()), _FakeFileUploader(), const Uuid());
    when(repository.transformEmailContent(any, any, any)).thenAnswer((invocation) async {
      final contents = invocation.positionalArguments[0] as List<EmailContent>;
      final cidUrls = invocation.positionalArguments[1] as Map<String, String>;
      final configuration = invocation.positionalArguments[2] as TransformConfiguration;
      return Future.wait(contents.map((content) => analyzer.transformEmailContent(content, cidUrls, configuration)));
    });
  });

  tearDown(() => PlatformInfo.isTestingForWeb = false);

  void stubEmail(Email email) {
    when(repository.getEmailContent(session, accountId, emailId)).thenAnswer((_) async => email);
  }

  /// Starts the open-email request as the email view makes it; the events are collected as they come.
  List<Either<Failure, Success>> open({bool defer = true, bool photos = true}) {
    final events = <Either<Failure, Success>>[];
    interactor
        .execute(session, accountId, emailId, downloadUrl, TransformConfiguration.forPreviewEmailOnWeb(),
            showInlinePhotos: photos, deferInlineImages: defer)
        .listen(events.add);
    return events;
  }

  Iterable<T> only<T>(List<Either<Failure, Success>> events) =>
      events.map((e) => e.fold<Success?>((_) => null, (s) => s)).whereType<T>();

  List<String> photoBlobs(Email email) => email.attachments!.map((part) => part.blobId!.value).toList();

  group('GetEmailContentInteractor::deferInlineImages:: (rf13)::', () {
    test('text first: the body is returned with a placeholder per picture before any download has finished', () async {
      final email = loadMimeFixture('apple_three_photos');
      for (final blob in photoBlobs(email)) {
        dio.answerFor(blob);          // nothing answers yet
      }
      stubEmail(email);

      final events = open();
      await pumpEventQueue();

      final success = only<GetEmailContentSuccess>(events).single;
      final images = parse(success.htmlEmailContent).querySelectorAll('img[data-rf-cid]');
      expect(images, hasLength(3));
      expect(images.map((img) => img.attributes['data-rf-state']), everyElement('pending'));
      expect(success.htmlEmailContent, isNot(contains('image/png;base64')));
      expect(success.htmlEmailContent, contains('>one<'));
      expect(success.inlineImages, hasLength(3));
      expect(only<GetEmailContentInlineImageSuccess>(events), isEmpty);
      expect(dio.requested, hasLength(3), reason: 'the three downloads have been started, each once');
    });

    test('each picture is reported when its own blob arrives, in the order they arrive', () async {
      final email = loadMimeFixture('apple_three_photos');
      final blobs = photoBlobs(email);
      final answers = [for (final blob in blobs) dio.answerFor(blob)];
      stubEmail(email);
      final events = open();
      await pumpEventQueue();

      answers[1].complete(Uint8List.fromList([1, 2, 3]));
      await pumpEventQueue();
      expect(only<GetEmailContentInlineImageSuccess>(events).map((s) => s.cid), ['rf-photo-6-${blobs[1]}']);

      answers[2].complete(Uint8List.fromList([4, 5, 6]));
      answers[0].complete(Uint8List.fromList([7, 8, 9]));
      await pumpEventQueue();

      final arrived = only<GetEmailContentInlineImageSuccess>(events).toList();
      expect(arrived.map((s) => s.cid).toSet(), {for (var i = 0; i < 3; i++) 'rf-photo-${[4, 6, 8][i]}-${blobs[i]}'});
      for (final picture in arrived) {
        expect(picture.source, startsWith('data:image/png;base64,'));
        expect(picture.emailId, email.id);
      }
      expect(only<GetEmailContentInlineImageFailed>(events), isEmpty);
      expect(dio.requested, hasLength(3), reason: 'each blob was requested once');
    });

    test('a picture that fails is reported as failed; the text and the other pictures are not affected', () async {
      final email = loadMimeFixture('apple_three_photos');
      final blobs = photoBlobs(email);
      final answers = [for (final blob in blobs) dio.answerFor(blob)];
      stubEmail(email);
      final events = open();
      await pumpEventQueue();

      answers[1].completeError(Exception('500'));
      answers[0].complete(Uint8List.fromList([1]));
      answers[2].complete(Uint8List.fromList([2]));
      await pumpEventQueue();

      expect(only<GetEmailContentInlineImageFailed>(events).map((s) => s.cid), ['rf-photo-6-${blobs[1]}']);
      expect(only<GetEmailContentInlineImageSuccess>(events), hasLength(2));
      expect(events.where((e) => e.isLeft()), isEmpty, reason: 'no failure state, so no error toast for one picture');
      expect(only<GetEmailContentSuccess>(events), hasLength(1));
    });

    test('without the request the pictures are fetched before the body is returned, as before', () async {
      final email = loadMimeFixture('apple_three_photos');
      stubEmail(email);

      final events = open(defer: false);
      await pumpEventQueue();

      final success = only<GetEmailContentSuccess>(events).single;
      expect(parse(success.htmlEmailContent).querySelectorAll('img[data-rf-cid]'), isEmpty);
      expect('image/png;base64'.allMatches(success.htmlEmailContent), hasLength(3));
      expect(only<GetEmailContentInlineImageSuccess>(events), isEmpty);
      expect(dio.requested, hasLength(3));
    });

    test('an email without inline pictures has nothing to defer', () async {
      stubEmail(loadMimeFixture('attachment_photo'));

      final events = open();
      await pumpEventQueue();

      expect(only<GetEmailContentSuccess>(events), hasLength(1));
      expect(only<GetEmailContentInlineImageSuccess>(events), isEmpty);
      expect(dio.requested, isEmpty);
    });

    test('a calendar invitation is not deferred (its own view shows the HTML)', () async {
      final image = EmailBodyPart(
        partId: PartId('2'),
        blobId: Id('blob-image'),
        type: MediaType('image', 'png'),
        disposition: 'inline',
        cid: 'logo@x',
        name: 'logo.png',
      );
      final calendar = EmailBodyPart(
        partId: PartId('3'),
        blobId: Id('blob-ics'),
        type: MediaType('text', 'calendar'),
        name: 'invite.ics',
      );
      stubEmail(Email(
        id: emailId,
        htmlBody: {EmailBodyPart(partId: PartId('1'), type: MediaType('text', 'html'))},
        bodyValues: {
          PartId('1'): EmailBodyValue(value: '<p>invite <img src="cid:logo@x"></p>', isEncodingProblem: false, isTruncated: false),
        },
        attachments: {image, calendar},
      ));

      final events = open();
      await pumpEventQueue();

      final success = only<GetEmailContentSuccess>(events).single;
      expect(success.htmlEmailContent, contains('base64,'), reason: 'fetched before the body is returned');
      expect(parse(success.htmlEmailContent).querySelectorAll('img[data-rf-cid]'), isEmpty);
      expect(only<GetEmailContentInlineImageSuccess>(events), isEmpty);
    });

    test('a real cid picture (Gmail style) is deferred like a photo, and a type a browser cannot label is sent as jpeg', () async {
      final icon = EmailBodyPart(
        partId: PartId('2'),
        blobId: Id('blob-icon'),
        type: MediaType('image', 'x-icon'),
        disposition: 'inline',
        cid: 'icon@x',
        name: 'favicon.ico',
      );
      stubEmail(Email(
        id: emailId,
        htmlBody: {EmailBodyPart(partId: PartId('1'), type: MediaType('text', 'html'))},
        bodyValues: {
          PartId('1'): EmailBodyValue(value: '<p>hi <img src="cid:icon@x" width="16" height="16"></p>', isEncodingProblem: false, isTruncated: false),
        },
        attachments: {icon},
      ));

      final events = open();
      await pumpEventQueue();

      final image = parse(only<GetEmailContentSuccess>(events).single.htmlEmailContent).querySelector('img')!;
      expect(image.attributes['data-rf-cid'], 'icon@x');
      expect(image.attributes['width'], '16', reason: 'its own size is kept');
      expect(only<GetEmailContentInlineImageSuccess>(events).single.source, startsWith('data:image/jpeg;base64,'));
    });

    test('a cid with markup in it: the sanitizer drops that source, nothing is injected, the image is reported as failed', () async {
      final nasty = EmailBodyPart(
        partId: PartId('2'),
        blobId: Id('blob-nasty'),
        type: MediaType('image', 'png'),
        disposition: 'inline',
        cid: 'a"><script>x()</script>',
        name: 'n.png',
      );
      stubEmail(Email(
        id: emailId,
        htmlBody: {EmailBodyPart(partId: PartId('1'), type: MediaType('text', 'html'))},
        bodyValues: {
          PartId('1'): EmailBodyValue(value: '<p><img src="cid:a&quot;&gt;&lt;script&gt;x()&lt;/script&gt;"></p>', isEncodingProblem: false, isTruncated: false),
        },
        attachments: {nasty},
      ));

      final events = open();
      await pumpEventQueue();

      for (final success in only<GetEmailContentSuccess>(events)) {
        expect(parse(success.htmlEmailContent).querySelectorAll('script'), isEmpty);
      }
      expect(only<GetEmailContentInlineImageSuccess>(events), isEmpty);
      expect(only<GetEmailContentInlineImageFailed>(events).map((s) => s.cid), ['a"><script>x()</script>']);
    });

    test('the dedupe of the view: layout 15 is drawn inline and no longer listed under the attachments', () async {
      stubEmail(loadMimeFixture('outlook_signature'));

      final events = open();
      await pumpEventQueue();

      final success = only<GetEmailContentSuccess>(events).single;
      expect(success.attachments, isEmpty);
      expect(success.inlineImages, hasLength(1));
    });

    test('without showInlinePhotos (the composer) nothing is deduped and nothing is deferred', () async {
      stubEmail(loadMimeFixture('outlook_signature'));

      final events = <Either<Failure, Success>>[];
      interactor
          .execute(session, accountId, emailId, downloadUrl, TransformConfiguration.forPreviewEmailOnWeb())
          .listen(events.add);
      await pumpEventQueue();

      final success = only<GetEmailContentSuccess>(events).single;
      expect(success.attachments, hasLength(1), reason: 'as in rf12: no disposition + cid is listed and drawn');
      expect(only<GetEmailContentInlineImageSuccess>(events), isEmpty);
    });

    test('only the opened email in the email view defers its pictures (that call and its retry); the thread action reactor, the .eml preview and the composer never do', () {
      final askers = {
        for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
          f.path.replaceAll(Platform.pathSeparator, '/'): 'deferInlineImages: '.allMatches(f.readAsStringSync()).length,
      }..removeWhere((_, count) => count == 0);

      expect(askers, {
        // the use case only passes the flag on (to the server fetch and to both retries)
        'lib/features/email/domain/usecases/get_email_content_interactor.dart': 3,
        // the call that loads the opened email and its retry, on the web only
        'lib/features/email/presentation/controller/single_email_controller.dart': 2,
      });
      expect('deferInlineImages: PlatformInfo.isWeb'.allMatches(File('lib/features/email/presentation/controller/single_email_controller.dart').readAsStringSync()).length, 2);
      for (final composerFile in Directory('lib/features/composer')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        expect(composerFile.readAsStringSync().contains('deferInlineImages'), isFalse, reason: composerFile.path);
      }
    });
  });
}
