import 'package:core/presentation/utils/html_transformer/dom/image_transformers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' show parse;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:model/email/attachment.dart';
import 'package:tmail_ui_user/features/email/presentation/model/email_loaded.dart';

/// rf13: EmailLoaded.displayHtml is what the viewer shows (inline images may still be placeholders);
/// EmailLoaded.htmlContent is what Reply, Forward and print take.
void main() {
  const placeholder = ImageTransformer.placeholderSrc;
  final first = Attachment(blobId: Id('b1'), cid: 'one@x', type: MediaType('image', 'png'), name: 'one.png');
  final second = Attachment(blobId: Id('b2'), cid: 'two@x', type: MediaType('image', 'png'), name: 'two.png');
  const html = '<html><head></head><body><p>text</p>'
      '<img src="$placeholder" id="cid:one@x" data-rf-cid="one@x" data-rf-state="pending" data-rf-ratio="50.0 / 20.0" style="width:50px">'
      '<img src="$placeholder" id="cid:two@x" data-rf-cid="two@x" data-rf-state="pending">'
      '</body></html>';

  EmailLoaded loaded({
    Map<String, String> sources = const {},
    Set<String> failed = const {},
    String? displayHtml,
  }) =>
      EmailLoaded(
        htmlContent: displayHtml ?? html,
        attachments: const [],
        inlineImages: [first, second],
        inlineImageSources: sources,
        failedInlineImages: failed,
      );

  List<String?> attrs(String html, String name) => parse(html).querySelectorAll('img').map((i) => i.attributes[name]).toList();

  group('EmailLoaded::htmlContent (what Reply, Forward and print take)::', () {
    test('every picture that has arrived is inlined as its data: URI and the placeholder markup is gone', () {
      final email = loaded(sources: {
        'one@x': 'data:image/png;base64,AAAA',
        'two@x': 'data:image/jpeg;base64,BBBB',
      });

      expect(attrs(email.htmlContent, 'src'), ['data:image/png;base64,AAAA', 'data:image/jpeg;base64,BBBB']);
      expect(attrs(email.htmlContent, 'id'), ['cid:one@x', 'cid:two@x'], reason: 'the composer finds the image by this id');
      expect(attrs(email.htmlContent, ImageTransformer.cidAttribute), [null, null]);
      expect(attrs(email.htmlContent, ImageTransformer.stateAttribute), [null, null]);
      expect(attrs(email.htmlContent, ImageTransformer.ratioAttribute), [null, null]);
      expect(attrs(email.htmlContent, 'style'), ['width:50px', null]);
      expect(email.htmlContent, contains('<p>text</p>'));
    });

    test('a picture still loading or failed goes back to its cid: source (the composer attaches it by its cid)', () {
      final email = loaded(sources: {'one@x': 'data:image/png;base64,AAAA'}, failed: {'two@x'});

      expect(attrs(email.htmlContent, 'src'), ['data:image/png;base64,AAAA', 'cid:two@x']);
    });

    test('nothing arrived yet: both are cid: sources, and what the viewer shows is untouched', () {
      final email = loaded();

      expect(attrs(email.htmlContent, 'src'), ['cid:one@x', 'cid:two@x']);
      expect(email.displayHtml, html);
      expect(attrs(email.displayHtml, 'src'), [placeholder, placeholder]);
    });

    test('an HTML without placeholders is returned as the very same string', () {
      const plain = '<html><head></head><body><p>hello <img src="data:image/png;base64,AAAA"></p></body></html>';

      expect(identical(loaded(displayHtml: plain).htmlContent, plain), isTrue);
      expect(resolveInlineImagePlaceholders(plain, const {}), plain);
    });

    test('the resolved HTML is computed once per EmailLoaded', () {
      final email = loaded(sources: {'one@x': 'data:image/png;base64,AAAA'});

      expect(identical(email.htmlContent, email.htmlContent), isTrue);
    });
  });

  group('EmailLoaded::pictures::', () {
    test('hasPendingInlineImages: true until every placeholder has its picture or has failed', () {
      expect(loaded().hasPendingInlineImages, isTrue);
      expect(loaded(sources: {'one@x': 'data:image/png;base64,AAAA'}).hasPendingInlineImages, isTrue);
      expect(loaded(sources: {'one@x': 'data:image/png;base64,AAAA'}, failed: {'two@x'}).hasPendingInlineImages, isFalse);
      expect(loaded(sources: {'one@x': 'x', 'two@x': 'y'}).hasPendingInlineImages, isFalse);
    });

    test('an email whose HTML has no placeholders is never pending, however many inline images it lists', () {
      expect(loaded(displayHtml: '<html><body><img src="data:image/png;base64,AAAA"></body></html>').hasPendingInlineImages, isFalse);
    });

    test('copyWith keeps what it is not asked to change, and a picture arriving makes it a different value', () {
      final before = loaded();
      final after = before.copyWith(inlineImageSources: {'one@x': 'data:image/png;base64,AAAA'});

      expect(after.displayHtml, before.displayHtml);
      expect(after.inlineImages, before.inlineImages);
      expect(after.failedInlineImages, before.failedInlineImages);
      expect(after, isNot(equals(before)));
      expect(after, equals(before.copyWith(inlineImageSources: {'one@x': 'data:image/png;base64,AAAA'})));
      expect(before.copyWith(failedInlineImages: {'two@x'}), isNot(equals(before)));
    });

    test('copyWith(htmlContent:) changes what is displayed', () {
      expect(loaded().copyWith(htmlContent: '<p>new</p>').displayHtml, '<p>new</p>');
    });
  });
}
