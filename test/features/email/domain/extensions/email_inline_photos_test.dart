import 'dart:convert' show HtmlEscape;
import 'dart:typed_data';

import 'package:core/data/network/dio_client.dart';
import 'package:core/presentation/utils/html_transformer/html_transform.dart';
import 'package:core/presentation/utils/html_transformer/transform_configuration.dart';
import 'package:dio/dio.dart' show CancelToken, Options, ProgressCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' show parse;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_body_part.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_body_value.dart';
import 'package:model/email/attachment.dart';
import 'package:model/extensions/email_extension.dart';
import 'package:model/extensions/list_attachment_extension.dart';
import 'package:model/extensions/list_email_content_extension.dart';
import 'package:tmail_ui_user/features/email/domain/extensions/email_attachment_classifier_extension.dart';

import '../../../../fixtures/account_fixtures.dart';
import '../../../../fixtures/mime_fixtures.dart';

/// Answers every download with a few bytes and keeps the URLs it was asked for.
class _ImageDioClient extends Fake implements DioClient {
  final requested = <String>[];

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    requested.add(path);
    return Uint8List.fromList([137, 80, 78, 71]);
  }
}

/// What the email view shows for an email: the body HTML, the attachment panel and the inline images.
class Shown {
  final String html;
  final List<Attachment> panel;
  final List<Attachment> inline;

  Shown(Email email)
      : html = email.emailContentList.asHtmlString,
        panel = email.toPresentationAttachments().attachments,
        inline = email.toPresentationAttachments().inlineImages;

  List<String?> get panelNames => panel.map((a) => a.name ?? a.type?.mimeType).toList();
  List<String?> get inlineCids => inline.map((a) => a.cid).toList();
}

/// rf11: the email as fetched. rf12: the email view's copy.
Shown rf11(Email email) => Shown(email);
Shown rf12(Email email) => Shown(email.withInlinePhotos());

List<String> cidsIn(String html) =>
    RegExp(r'<img[^>]*src="cid:([^"]+)"').allMatches(html).map((m) => m.group(1)!).toList();

EmailBodyPart partOf(Email email, String partId) =>
    email.attachments!.firstWhere((part) => part.partId?.value == partId);

String photoCid(Email email, String partId) => 'rf-photo-$partId-${partOf(email, partId).blobId!.value}';

const photoLayouts = ['apple_ios_photo', 'apple_three_photos', 'apple_plain_photo', 'no_disposition_no_cid'];

void main() {
  group('Email::withInlinePhotos:: real engine layouts (test/fixtures/mime)::', () {
    test('1 apple_ios_photo: the photo is in the body between the two HTML fragments, not in the panel', () {
      final email = loadMimeFixture('apple_ios_photo');
      final cid = photoCid(email, '4');

      final before = rf11(email);
      expect(before.inline, isEmpty, reason: 'rf11: the photo is not an inline image');
      expect(before.panel, isEmpty, reason: 'rf11: and not in the panel');
      expect(cidsIn(before.html), isEmpty, reason: 'rf11: and not in the body');

      final after = rf12(email);
      expect(cidsIn(after.html), [cid]);
      expect(after.html.indexOf('Hi, this is a test email.'), lessThan(after.html.indexOf('cid:$cid')));
      expect(after.html.indexOf('cid:$cid'), lessThan(after.html.indexOf('<div><br></div>')));
      expect(after.inlineCids, [cid]);
      expect(after.inline.single.blobId, partOf(email, '4').blobId);
      expect(after.panel, isEmpty);
    });

    test('2 apple_three_photos: three photos in order, the text between them intact, none in the panel', () {
      final email = loadMimeFixture('apple_three_photos');
      final cids = [for (final partId in ['4', '6', '8']) photoCid(email, partId)];

      expect(rf11(email).inline, isEmpty);
      expect(rf11(email).panel, isEmpty);

      final after = rf12(email);
      expect(cidsIn(after.html), cids);
      final at = [
        for (final marker in [
          '>one<', 'cid:${cids[0]}', '>two<', 'cid:${cids[1]}', '>three<', 'cid:${cids[2]}', '>end<',
        ]) after.html.indexOf(marker),
      ];
      expect(at.every((i) => i >= 0), isTrue, reason: '$at');
      expect([...at]..sort(), at, reason: 'text, photo, text, photo, text, photo, text in this order');
      expect(after.inlineCids, cids);
      expect(after.inline.map((a) => a.blobId).toSet(), hasLength(3));
      expect(after.panel, isEmpty);
    });

    test('3 apple_plain_photo: the photo follows the text (plain text email), not in the panel', () {
      final email = loadMimeFixture('apple_plain_photo');
      final cid = photoCid(email, '2');
      final blob = partOf(email, '2').blobId!.value;

      expect(rf11(email).inline, isEmpty);
      expect(rf11(email).panel, isEmpty);

      final after = rf12(email);
      expect(
        after.html,
        'Hi, plain text with a photo.<br/></br>'
        '<div><img src="cid:$cid" data-mimetype="image/png" alt="IMG_0001.png" '
        'style="max-width:100%;height:auto"></div>',
      );
      expect(after.inline.single.blobId!.value, blob);
      expect(after.inline.single.disposition, ContentDisposition.inline);
      expect(after.panel, isEmpty);
    });

    test('4 apple_heic: a browser cannot draw HEIC, so it is in the panel and not a broken inline image', () {
      final email = loadMimeFixture('apple_heic');

      expect(rf11(email).panel, isEmpty, reason: 'rf11: lost');

      final after = rf12(email);
      expect(cidsIn(after.html), isEmpty);
      expect(after.html, contains('heic photo'));
      expect(after.inline, isEmpty);
      expect(after.panelNames, ['IMG_0002.HEIC']);
      expect(after.panel.single.type?.mimeType, 'image/heic');
      expect(after.panel.single.blobId, partOf(email, '2').blobId);
    });

    test('5 no_disposition_no_cid: an image part in htmlBody without disposition is in the body, not in the panel', () {
      final email = loadMimeFixture('no_disposition_no_cid');
      final cid = photoCid(email, '2');

      expect(rf11(email).inline, isEmpty);
      expect(rf11(email).panel, isEmpty);

      final after = rf12(email);
      expect(cidsIn(after.html), [cid]);
      expect(after.html.indexOf('no disposition'), lessThan(after.html.indexOf('cid:$cid')));
      expect(after.inlineCids, [cid]);
      expect(after.panel, isEmpty);
    });

    test('6 apple_inline_pdf: unchanged, the PDF is in the panel', () {
      final email = loadMimeFixture('apple_inline_pdf');
      expect(identical(email.withInlinePhotos(), email), isTrue);
      expect(rf12(email).panelNames, ['Quote.pdf']);
      expect(rf12(email).inline, isEmpty);
      expect(cidsIn(rf12(email).html), isEmpty);
    });

    test('7 attachment_photo: unchanged, the photo is in the panel and not in the body', () {
      final email = loadMimeFixture('attachment_photo');
      expect(identical(email.withInlinePhotos(), email), isTrue);
      expect(rf12(email).panelNames, ['photo.jpg']);
      expect(rf12(email).inline, isEmpty);
      expect(cidsIn(rf12(email).html), isEmpty);
    });

    test('8 calendar_invite: unchanged', () {
      final email = loadMimeFixture('calendar_invite');
      expect(identical(email.withInlinePhotos(), email), isTrue);
      expect(rf12(email).panel.map((a) => a.type?.mimeType), ['text/calendar']);
      expect(rf12(email).inline, isEmpty);
      expect(rf12(email).html, rf11(email).html);
    });

    test('9 content_location: (rf13) the <img src="photo.png"> is drawn from the part with that Content-Location', () {
      final email = loadMimeFixture('content_location');
      final cid = 'rf-loc-2-${partOf(email, '2').blobId!.value}';

      expect(rf11(email).panelNames, ['photo.png'], reason: 'rf11 and rf12: listed, and the relative image is not drawn');
      expect(rf11(email).inline, isEmpty);

      final after = rf12(email);
      expect(cidsIn(after.html), [cid]);
      expect(after.html, isNot(contains('src="photo.png"')));
      expect(after.html, contains('data-mimetype="image/png"'));
      expect(after.inlineCids, [cid]);
      expect(after.panel, isEmpty);
    });

    test('10 data_uri: unchanged, the data: image is part of the HTML and nothing is listed', () {
      final email = loadMimeFixture('data_uri');
      expect(identical(email.withInlinePhotos(), email), isTrue);
      expect(rf12(email).panel, isEmpty);
      expect(rf12(email).inline, isEmpty);
      expect(rf12(email).html, contains('src="data:image/png;base64,'));
    });

    test('11 forwarded_rfc822: unchanged, the attached message is in the panel', () {
      final email = loadMimeFixture('forwarded_rfc822');
      expect(identical(email.withInlinePhotos(), email), isTrue);
      expect(rf12(email).panel.map((a) => a.type?.mimeType), ['message/rfc822']);
      expect(rf12(email).inline, isEmpty);
    });

    test('12 gmail_inline: unchanged, inline by its real cid, not in the panel', () {
      final email = loadMimeFixture('gmail_inline');
      expect(identical(email.withInlinePhotos(), email), isTrue);
      expect(rf12(email).inlineCids, ['ii_m2abc123']);
      expect(rf12(email).panel, isEmpty);
      expect(cidsIn(rf12(email).html), ['ii_m2abc123']);
    });

    test('13 mixed_inline_and_attachment: one inline and one in the panel, no duplicate', () {
      final email = loadMimeFixture('mixed_inline_and_attachment');
      expect(identical(email.withInlinePhotos(), email), isTrue);
      expect(rf12(email).inlineCids, ['ii_inline1']);
      expect(rf12(email).panelNames, ['attached.png']);
    });

    test('14 orphan_cid: unchanged, the image nobody references is in the panel', () {
      final email = loadMimeFixture('orphan_cid');
      expect(identical(email.withInlinePhotos(), email), isTrue);
      expect(rf12(email).panelNames, ['orphan.png']);
      expect(rf12(email).inline, isEmpty);
    });

    test('15 outlook_signature: unchanged, inline by its cid (rf11 also lists it in the panel: no disposition + cid)', () {
      final email = loadMimeFixture('outlook_signature');
      expect(identical(email.withInlinePhotos(), email), isTrue);
      expect(rf12(email).inlineCids, ['image001.png@01DB2A3B.4C5D6E70']);
      // Not from this change: an image with a cid and no disposition satisfies the "outside" predicate as well,
      // and the classifier only removes the unreferenced ones from the panel. Pinned so a change shows up.
      expect(rf12(email).panelNames, ['image001.png']);
      expect(rf12(email).panel, rf11(email).panel);
    });

    test('every layout other than 1-5 gives exactly what rf11 gave (html, panel, inline images)', () {
      for (final key in mimeUnchangedLayouts) {
        final email = loadMimeFixture(key);
        final before = rf11(email);
        final after = rf12(email);
        expect(after.html, before.html, reason: key);
        expect(after.panel, before.panel, reason: key);
        expect(after.inline, before.inline, reason: key);
      }
    });

    test('no image is shown twice: inline images are not in the panel, each is in the body once', () {
      // outlook_signature is the one layout where rf11 itself lists an inline image in the panel too (test 15).
      for (final key in [
        ...photoLayouts,
        'apple_heic',
        'content_location',
        ...mimeUnchangedLayouts.where((k) => k != 'outlook_signature'),
      ]) {
        final after = rf12(loadMimeFixture(key));
        final inlineBlobs = after.inline.map((a) => a.blobId).toList();
        final panelBlobs = after.panel.map((a) => a.blobId).toList();
        expect(inlineBlobs.toSet(), hasLength(inlineBlobs.length), reason: '$key: an inline image twice');
        expect(panelBlobs.toSet(), hasLength(panelBlobs.length), reason: '$key: a panel entry twice');
        expect(inlineBlobs.toSet().intersection(panelBlobs.toSet()), isEmpty, reason: '$key: inline and panel');
        final shownCids = cidsIn(after.html);
        expect(shownCids.toSet(), hasLength(shownCids.length), reason: '$key: an <img> twice in the body');
        for (final cid in after.inlineCids) {
          expect(shownCids, contains(cid), reason: '$key: $cid is registered but not shown');
        }
      }
    });
  });

  group('Email::withInlinePhotos:: through the real HTML transform (sanitizer + image transformer)::', () {
    test('3 photos: each <img> becomes a data: URI of its own type, keeps its cid id and its width limit, in order', () async {
      final shownEmail = loadMimeFixture('apple_three_photos').withInlinePhotos();
      final classified = shownEmail.toPresentationAttachments();
      final dio = _ImageDioClient();

      final html = await HtmlTransform(dio, const HtmlEscape()).transformToHtml(
        htmlContent: shownEmail.emailContentList.asHtmlString,
        transformConfiguration: TransformConfiguration.forPreviewEmailOnWeb(),
        mapCidImageDownloadUrl: classified.inlineImages.toMapCidImageDownloadUrl(
          accountId: AccountFixtures.aliceAccountId,
          downloadUrl: 'https://download.example.com/{accountId}/{blobId}/{name}',
        ),
      );

      final images = parse(html).querySelectorAll('img');
      expect(images, hasLength(3));
      expect(images.map((img) => img.attributes['id']).toList(), classified.inlineImages.map((a) => 'cid:${a.cid}').toList());
      for (final img in images) {
        expect(img.attributes['src'], startsWith('data:image/png;base64,'));
        expect(img.attributes['style'], matches(RegExp(r'max-width:\s*100%')));
      }
      expect(dio.requested, hasLength(3));
      for (final a in classified.inlineImages) {
        expect(dio.requested.where((url) => url.contains(a.blobId!.value)), hasLength(1));
      }
      final at = [
        html.indexOf('>one<'),
        html.indexOf('id="cid:${classified.inlineImages[0].cid}"'),
        html.indexOf('>two<'),
        html.indexOf('id="cid:${classified.inlineImages[1].cid}"'),
        html.indexOf('>three<'),
        html.indexOf('id="cid:${classified.inlineImages[2].cid}"'),
      ];
      expect(at.every((i) => i >= 0), isTrue, reason: '$at');
      expect([...at]..sort(), at, reason: 'text and photos in the order of the message');
    });

    test('plain text message: the photo follows the text', () async {
      final shownEmail = loadMimeFixture('apple_plain_photo').withInlinePhotos();
      final classified = shownEmail.toPresentationAttachments();

      final html = await HtmlTransform(_ImageDioClient(), const HtmlEscape()).transformToHtml(
        htmlContent: shownEmail.emailContentList.asHtmlString,
        transformConfiguration: TransformConfiguration.forPreviewEmailOnWeb(),
        mapCidImageDownloadUrl: classified.inlineImages.toMapCidImageDownloadUrl(
          accountId: AccountFixtures.aliceAccountId,
          downloadUrl: 'https://download.example.com/{accountId}/{blobId}/{name}',
        ),
      );

      expect(html.indexOf('plain text with a photo'), lessThan(html.indexOf('<img')));
      expect(parse(html).querySelector('img')!.attributes['src'], startsWith('data:image/png;base64,'));
    });
  });

  group('Email::withInlinePhotos:: other emails::', () {
    EmailBodyPart htmlPart(String partId) => EmailBodyPart(partId: PartId(partId), type: MediaType('text', 'html'));
    EmailBodyPart plainPart(String partId) => EmailBodyPart(partId: PartId(partId), type: MediaType('text', 'plain'));
    EmailBodyPart mediaPart(
      String partId,
      String mime, {
      String? blob,
      String? disposition = 'inline',
      String? cid,
      String? name,
    }) {
      final type = MediaType.parse(mime);
      return EmailBodyPart(
        partId: PartId(partId),
        blobId: blob == null ? null : Id(blob),
        type: type,
        disposition: disposition,
        cid: cid,
        name: name,
      );
    }

    Email emailOf(List<EmailBodyPart> body, Map<String, String> texts, {Set<EmailBodyPart>? attachments}) => Email(
          id: EmailId(Id('e')),
          htmlBody: body.toSet(),
          bodyValues: {
            for (final e in texts.entries)
              PartId(e.key): EmailBodyValue(value: e.value, isEncodingProblem: false, isTruncated: false),
          },
          attachments: attachments ??
              body.where((part) => part.type?.type != 'text').toSet(),
        );

    test('jpeg, jpg, gif, webp and bmp photos are shown like png ones', () {
      for (final mime in ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp', 'image/bmp']) {
        final after = rf12(emailOf(
          [htmlPart('1'), mediaPart('2', mime, blob: 'b2')],
          {'1': '<p>hi</p>'},
        ));
        expect(cidsIn(after.html), ['rf-photo-2-b2'], reason: mime);
        expect(after.html, contains('data-mimetype="$mime"'), reason: mime);
        expect(after.panel, isEmpty, reason: mime);
        expect(after.inlineCids, ['rf-photo-2-b2'], reason: mime);
      }
    });

    test('types a browser cannot draw (heic, heif, tiff) or that can carry script (svg) go to the panel', () {
      for (final mime in ['image/heic', 'image/heif', 'image/tiff', 'image/svg+xml']) {
        final after = rf12(emailOf(
          [htmlPart('1'), mediaPart('2', mime, blob: 'b2', name: 'x')],
          {'1': '<p>hi</p>'},
        ));
        expect(cidsIn(after.html), isEmpty, reason: mime);
        expect(after.html, '<p>hi</p>', reason: mime);
        expect(after.inline, isEmpty, reason: mime);
        expect(after.panelNames, ['x'], reason: mime);
      }
    });

    test('a non-image part without cid in htmlBody (pdf, binary, audio, video) is listed, not lost', () {
      for (final mime in ['application/pdf', 'application/octet-stream', 'audio/mpeg', 'video/mp4']) {
        final after = rf12(emailOf(
          [htmlPart('1'), mediaPart('2', mime, blob: 'b2', name: 'x')],
          {'1': '<p>hi</p>'},
        ));
        expect(cidsIn(after.html), isEmpty, reason: mime);
        expect(after.html, '<p>hi</p>', reason: mime);
        expect(after.panelNames, ['x'], reason: mime);
        expect(after.inline, isEmpty, reason: mime);
      }
    });

    test('a photo with disposition attachment is listed in the panel, not shown in the body', () {
      final after = rf12(emailOf(
        [htmlPart('1'), mediaPart('2', 'image/jpeg', blob: 'b2', disposition: 'attachment', name: 'p.jpg')],
        {'1': '<p>hi</p>'},
      ));
      expect(cidsIn(after.html), isEmpty);
      expect(after.panelNames, ['p.jpg']);
      expect(after.inline, isEmpty);
    });

    test('a photo that has a real cid is left alone (the HTML decides where it is)', () {
      final email = emailOf(
        [htmlPart('1'), mediaPart('2', 'image/png', blob: 'b2', cid: 'real@x')],
        {'1': '<p><img src="cid:real@x"></p>'},
      );
      expect(identical(email.withInlinePhotos(), email), isTrue);
      expect(rf12(email).inlineCids, ['real@x']);
      expect(rf12(email).panel, isEmpty);
    });

    test('an empty cid is no cid', () {
      final after = rf12(emailOf(
        [htmlPart('1'), mediaPart('2', 'image/png', blob: 'b2', cid: '')],
        {'1': '<p>hi</p>'},
      ));
      expect(cidsIn(after.html), ['rf-photo-2-b2']);
      expect(after.panel, isEmpty);
    });

    test('a photo without blob id cannot be downloaded: not made an inline image', () {
      final after = rf12(emailOf(
        [htmlPart('1'), mediaPart('2', 'image/png')],
        {'1': '<p>hi</p>'},
      ));
      expect(cidsIn(after.html), isEmpty);
      expect(after.inline, isEmpty);
    });

    test('nothing is lost when the server leaves the part out of attachments: a HEIC is listed, a photo is shown', () {
      final heic = rf12(emailOf(
        [htmlPart('1'), mediaPart('2', 'image/heic', blob: 'b2', name: 'x.heic')],
        {'1': '<p>hi</p>'},
        attachments: <EmailBodyPart>{},
      ));
      expect(heic.panelNames, ['x.heic']);
      expect(cidsIn(heic.html), isEmpty);

      final photo = rf12(emailOf(
        [htmlPart('1'), mediaPart('2', 'image/png', blob: 'b2')],
        {'1': '<p>hi</p>'},
        attachments: <EmailBodyPart>{},
      ));
      expect(photo.inlineCids, ['rf-photo-2-b2']);
      expect(photo.panel, isEmpty);
    });

    group('Content-Location::', () {
      EmailBodyPart located(String partId, String blob, String location,
              {String mime = 'image/png', String? disposition = 'inline', String? cid}) =>
          EmailBodyPart(
            partId: PartId(partId),
            blobId: Id(blob),
            type: MediaType.parse(mime),
            disposition: disposition,
            location: location,
            cid: cid,
            name: 'x',
          );

      Email withLocated(String html, Set<EmailBodyPart> attachments) => Email(
            id: EmailId(Id('e')),
            htmlBody: {htmlPart('1')},
            bodyValues: {PartId('1'): EmailBodyValue(value: html, isEncodingProblem: false, isTruncated: false)},
            attachments: attachments,
          );

      test('every <img> whose src is exactly the location is drawn from that part; the rest of the HTML is kept', () {
        final after = rf12(withLocated(
          '<p>a <img src="p.png" width="20"> b <img src="p.png"> <a href="p.png">link</a> <img src="other.png"></p>',
          {located('2', 'b2', 'p.png')},
        ));

        expect(cidsIn(after.html), ['rf-loc-2-b2', 'rf-loc-2-b2']);
        expect(after.html, contains('href="p.png"'), reason: 'only <img src> is rewritten');
        expect(after.html, contains('src="other.png"'));
        expect(after.html, contains('width="20"'));
        expect(after.inline, hasLength(1), reason: 'one part, however often the HTML shows it');
        expect(after.panel, isEmpty);
      });

      test('an absolute location works the same, and the remote image is no longer requested', () {
        final after = rf12(withLocated(
          '<img src="https://cdn.example.com/p.png">',
          {located('2', 'b2', 'https://cdn.example.com/p.png')},
        ));

        expect(cidsIn(after.html), ['rf-loc-2-b2']);
        expect(after.html, isNot(contains('cdn.example.com')));
      });

      test('nothing changes (the very same email) when no <img src> matches exactly', () {
        for (final html in ['<img src="P.png">', '<img src="./p.png">', '<img src="p.png?x=1">', '<a href="p.png">p.png</a>', '<p>p.png</p>']) {
          final email = withLocated(html, {located('2', 'b2', 'p.png')});
          expect(identical(email.withInlinePhotos(), email), isTrue, reason: html);
          expect(rf12(email).panelNames, ['x'], reason: html);
        }
      });

      test('a part that is an attachment, has a cid, cannot be drawn, or cannot be downloaded is left alone', () {
        for (final part in [
          located('2', 'b2', 'p.png', disposition: 'attachment'),
          located('2', 'b2', 'p.png', cid: 'c@x'),
          located('2', 'b2', 'p.png', mime: 'image/svg+xml'),
          located('2', 'b2', 'p.png', mime: 'image/heic'),
          located('2', 'b2', 'p.png', mime: 'application/pdf'),
          EmailBodyPart(partId: PartId('2'), type: MediaType('image', 'png'), location: 'p.png', disposition: 'inline'),
        ]) {
          final email = withLocated('<img src="p.png">', {part});
          expect(identical(email.withInlinePhotos(), email), isTrue, reason: '${part.type} ${part.disposition} ${part.cid}');
        }
      });

      test('two photos with two locations are both drawn, in the order of the HTML', () {
        final after = rf12(withLocated(
          '<img src="b.png"><img src="a.png">',
          {located('2', 'ba', 'a.png'), located('3', 'bb', 'b.png')},
        ));

        expect(cidsIn(after.html), ['rf-loc-3-bb', 'rf-loc-2-ba']);
        expect(after.inlineCids.toSet(), {'rf-loc-2-ba', 'rf-loc-3-bb'});
      });
    });

    test('a message that is only a photo (no text part at all) shows the photo', () {
      final after = rf12(emailOf([mediaPart('1', 'image/jpeg', blob: 'b1', name: 'only.jpg')], {}));
      expect(cidsIn(after.html), ['rf-photo-1-b1']);
      expect(after.panel, isEmpty);
      expect(after.inlineCids, ['rf-photo-1-b1']);
      expect(rf11(emailOf([mediaPart('1', 'image/jpeg', blob: 'b1', name: 'only.jpg')], {})).html, isEmpty,
          reason: 'rf11: an empty body');
    });

    test('the same photo twice (same blob) is two images with two different cids', () {
      final after = rf12(emailOf(
        [htmlPart('1'), mediaPart('2', 'image/png', blob: 'same'), htmlPart('3'), mediaPart('4', 'image/png', blob: 'same')],
        {'1': '<p>a</p>', '3': '<p>b</p>'},
      ));
      expect(cidsIn(after.html), ['rf-photo-2-same', 'rf-photo-4-same']);
      expect(after.inlineCids, ['rf-photo-2-same', 'rf-photo-4-same']);
      expect(after.html.indexOf('>b<'), greaterThan(after.html.indexOf('rf-photo-2-same')));
      expect(after.html.indexOf('>b<'), lessThan(after.html.indexOf('rf-photo-4-same')));
    });

    test('the order is the order of htmlBody, whatever the order of bodyValues is', () {
      final email = Email(
        id: EmailId(Id('e')),
        htmlBody: {htmlPart('1'), mediaPart('2', 'image/png', blob: 'b2'), htmlPart('3')},
        bodyValues: {
          PartId('3'): EmailBodyValue(value: '<p>after</p>', isEncodingProblem: false, isTruncated: false),
          PartId('1'): EmailBodyValue(value: '<p>before</p>', isEncodingProblem: false, isTruncated: false),
        },
        attachments: {mediaPart('2', 'image/png', blob: 'b2')},
      );
      final html = rf12(email).html;
      expect(html.indexOf('before'), lessThan(html.indexOf('cid:rf-photo-2-b2')));
      expect(html.indexOf('cid:rf-photo-2-b2'), lessThan(html.indexOf('after')));
    });

    test('text values that htmlBody does not list are not shown', () {
      final after = rf12(emailOf(
        [htmlPart('3'), mediaPart('4', 'image/png', blob: 'b4')],
        {'1': 'plain version', '3': '<p>html version</p>'},
      ));
      expect(after.html, isNot(contains('plain version')));
      expect(after.html, contains('html version'));
    });

    test('the file name is escaped in the alt attribute', () {
      final after = rf12(emailOf(
        [htmlPart('1'), mediaPart('2', 'image/png', blob: 'b2', name: 'a"><script>x()</script>.png')],
        {'1': '<p>hi</p>'},
      ));
      expect(after.html, isNot(contains('<script>')));
      expect(after.html, contains('alt="a&quot;&gt;&lt;script&gt;x()&lt;&#47;script&gt;.png"'));
    });

    test('the same email gives the same ids and HTML every time', () {
      final email = loadMimeFixture('apple_three_photos');
      expect(rf12(email).html, rf12(email).html);
      expect(rf12(email).inlineCids, rf12(email).inlineCids);
    });

    test('a real cid of the email is never taken by a photo without one', () {
      final after = rf12(emailOf(
        [htmlPart('1'), mediaPart('2', 'image/png', blob: 'b2', cid: 'real@x'), mediaPart('3', 'image/png', blob: 'b3')],
        {'1': '<p><img src="cid:real@x"></p>'},
      ));
      expect(after.inlineCids.toSet(), {'real@x', 'rf-photo-3-b3'});
      expect(after.inline, hasLength(2));
    });

    test('an email without htmlBody is returned as it is', () {
      final email = Email(id: EmailId(Id('e')));
      expect(identical(email.withInlinePhotos(), email), isTrue);
    });

    test('the email as fetched is not changed (the composer keeps using it)', () {
      final email = loadMimeFixture('apple_ios_photo');
      final htmlBody = email.htmlBody!.toList();
      final attachments = email.attachments!.toList();
      final bodyValues = Map.of(email.bodyValues!);
      final before = Shown(email);

      email.withInlinePhotos();

      expect(email.htmlBody!.toList(), htmlBody);
      expect(email.attachments!.toList(), attachments);
      expect(email.bodyValues, bodyValues);
      expect(Shown(email).html, before.html);
      expect(Shown(email).inline, isEmpty);
    });
  });
}
