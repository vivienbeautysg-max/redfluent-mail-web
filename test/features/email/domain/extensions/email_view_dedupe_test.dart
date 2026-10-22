import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_body_part.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_body_value.dart';
import 'package:tmail_ui_user/features/email/domain/extensions/email_attachment_classifier_extension.dart';

import '../../../../fixtures/mime_fixtures.dart';

/// rf13: what the email view lists under the attachments when an attachment is also drawn inline in the body
/// (toPresentationAttachments(hideDrawnInline: true)); the composer keeps the default (false).
void main() {
  List<String?> names(PresentationAttachments result) => result.attachments.map((a) => a.name).toList();
  List<String?> drawn(PresentationAttachments result) => result.inlineImages.map((a) => a.cid).toList();

  EmailBodyPart image(
    String partId,
    String blob, {
    String? cid,
    String? disposition,
    String name = 'p.png',
  }) =>
      EmailBodyPart(
        partId: PartId(partId),
        blobId: Id(blob),
        type: MediaType('image', 'png'),
        cid: cid,
        disposition: disposition,
        name: name,
      );

  Email emailWith(Set<EmailBodyPart> attachments, String html) => Email(
        id: EmailId(Id('e')),
        htmlBody: {EmailBodyPart(partId: PartId('1'), type: MediaType('text', 'html'))},
        bodyValues: {PartId('1'): EmailBodyValue(value: html, isEncodingProblem: false, isTruncated: false)},
        attachments: attachments,
      );

  group('toPresentationAttachments(hideDrawnInline:):: real engine layouts::', () {
    test('15 outlook_signature: drawn inline, no longer also listed (the default still lists it)', () {
      final email = loadMimeFixture('outlook_signature');

      final composer = email.toPresentationAttachments();
      expect(names(composer), ['image001.png']);
      expect(drawn(composer), ['image001.png@01DB2A3B.4C5D6E70']);

      final view = email.toPresentationAttachments(hideDrawnInline: true);
      expect(names(view), isEmpty);
      expect(drawn(view), ['image001.png@01DB2A3B.4C5D6E70']);
    });

    test('14 orphan_cid: not referenced by the body, so it is not drawn and stays listed', () {
      final view = loadMimeFixture('orphan_cid').toPresentationAttachments(hideDrawnInline: true);

      expect(names(view), ['orphan.png']);
      expect(drawn(view), isEmpty);
    });

    test('12 gmail_inline and 13 mixed_inline_and_attachment: the same with and without', () {
      for (final key in ['gmail_inline', 'mixed_inline_and_attachment']) {
        final email = loadMimeFixture(key);
        final without = email.toPresentationAttachments();
        final withHide = email.toPresentationAttachments(hideDrawnInline: true);
        expect(names(withHide), names(without), reason: key);
        expect(drawn(withHide), drawn(without), reason: key);
      }
      expect(names(loadMimeFixture('mixed_inline_and_attachment').toPresentationAttachments(hideDrawnInline: true)), ['attached.png']);
    });

    test('every layout but 15 is listed exactly as without the flag', () {
      for (final key in mimeUnchangedLayouts.where((key) => key != 'outlook_signature')) {
        final email = loadMimeFixture(key);
        final without = email.toPresentationAttachments();
        final withHide = email.toPresentationAttachments(hideDrawnInline: true);
        expect(withHide.attachments, without.attachments, reason: key);
        expect(withHide.inlineImages, without.inlineImages, reason: key);
      }
    });
  });

  group('toPresentationAttachments(hideDrawnInline:):: the rule::', () {
    test('disposition attachment is always listed, even when its cid is referenced (it is not drawn inline)', () {
      final view = emailWith(
        {image('2', 'b2', cid: 'c@x', disposition: 'attachment')},
        '<p><img src="cid:c@x"></p>',
      ).toPresentationAttachments(hideDrawnInline: true);

      expect(names(view), ['p.png']);
      expect(drawn(view), isEmpty);
    });

    test('no disposition + referenced cid: drawn, hidden from the list', () {
      final view = emailWith({image('2', 'b2', cid: 'c@x')}, '<p><img src="cid:c@x"></p>')
          .toPresentationAttachments(hideDrawnInline: true);

      expect(names(view), isEmpty);
      expect(drawn(view), ['c@x']);
    });

    test('disposition inline + referenced cid: drawn only, with or without the flag', () {
      final email = emailWith({image('2', 'b2', cid: 'c@x', disposition: 'inline')}, '<img src="cid:c@x">');

      expect(names(email.toPresentationAttachments()), isEmpty);
      expect(names(email.toPresentationAttachments(hideDrawnInline: true)), isEmpty);
      expect(drawn(email.toPresentationAttachments(hideDrawnInline: true)), ['c@x']);
    });

    test('no disposition + cid that nothing references: listed (and not drawn)', () {
      final view = emailWith({image('2', 'b2', cid: 'c@x')}, '<p>no pictures here</p>')
          .toPresentationAttachments(hideDrawnInline: true);

      expect(names(view), ['p.png']);
      expect(drawn(view), isEmpty);
    });

    test('the same picture attached once more (disposition attachment, same blob) is still listed: the match is by cid', () {
      final view = emailWith(
        {
          image('2', 'same', cid: 'c@x'),
          image('3', 'same', disposition: 'attachment', name: 'copy.png'),
        },
        '<img src="cid:c@x">',
      ).toPresentationAttachments(hideDrawnInline: true);

      expect(names(view), ['copy.png']);
      expect(drawn(view), ['c@x']);
    });

    test('an attachment that repeats the cid of a drawn picture is still listed: the disposition decides, not the cid', () {
      final view = emailWith(
        {
          image('2', 'drawn', cid: 'c@x'),
          image('3', 'copy', cid: 'c@x', disposition: 'attachment', name: 'copy.png'),
        },
        '<img src="cid:c@x">',
      ).toPresentationAttachments(hideDrawnInline: true);

      expect(names(view), ['copy.png']);
      expect(drawn(view), ['c@x']);
    });

    test('a disposition the view does not draw (neither inline nor missing) is listed', () {
      final view = emailWith({image('2', 'b2', cid: 'c@x', disposition: 'form-data')}, '<img src="cid:c@x">')
          .toPresentationAttachments(hideDrawnInline: true);

      expect(names(view), ['p.png']);
      expect(drawn(view), isEmpty);
    });

    test('a cid in the src is matched after trimming, like the transformer does', () {
      final view = emailWith({image('2', 'b2', cid: 'c@x')}, '<img src="cid:  c@x  ">')
          .toPresentationAttachments(hideDrawnInline: true);

      expect(names(view), isEmpty);
    });

    test('the default (the composer) lists it as before', () {
      final email = emailWith({image('2', 'b2', cid: 'c@x')}, '<img src="cid:c@x">');

      expect(names(email.toPresentationAttachments()), ['p.png']);
    });
  });
}
