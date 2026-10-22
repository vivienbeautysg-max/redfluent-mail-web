import 'dart:convert';
import 'dart:typed_data';

import 'package:core/data/network/dio_client.dart';
import 'package:core/presentation/utils/html_transformer/dom/image_transformers.dart';
import 'package:core/presentation/utils/html_transformer/html_transform.dart';
import 'package:core/presentation/utils/html_transformer/transform_configuration.dart';
import 'package:core/presentation/views/html_viewer/html_content_viewer_on_web_widget.dart';
import 'package:core/utils/html/html_interaction.dart';
import 'package:core/utils/html/html_template.dart';
import 'package:dio/dio.dart' show CancelToken, Options, ProgressCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' show parse;

/// Counts the downloads; a deferred image must never reach it.
class _CountingDioClient extends Fake implements DioClient {
  int calls = 0;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    calls++;
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  late _CountingDioClient dio;
  late HtmlTransform htmlTransform;

  setUp(() {
    dio = _CountingDioClient();
    htmlTransform = HtmlTransform(dio, const HtmlEscape());
  });

  Future<String> deferred(String html, {Map<String, String>? cidUrls}) => htmlTransform.transformToHtml(
        htmlContent: html,
        transformConfiguration: TransformConfiguration.forPreviewEmailOnWebWithDeferredImages(),
        mapCidImageDownloadUrl: cidUrls ?? const {},
      );

  group('ImageTransformer(deferCidImages: true)::', () {
    test('a cid: image becomes a placeholder that carries its cid and state, keeps its own markup, and starts no download', () async {
      final html = await deferred(
        '<p>x <img src="cid:logo@x" style="width:80px" alt="logo" width="80" height="20"></p>',
        cidUrls: {'logo@x': 'https://download.example.com/blob'},
      );

      final image = parse(html).querySelector('img')!;
      expect(image.attributes[ImageTransformer.cidAttribute], 'logo@x');
      expect(image.attributes[ImageTransformer.stateAttribute], 'pending');
      expect(image.attributes['src'], ImageTransformer.placeholderSrc);
      expect(image.attributes['id'], 'cid:logo@x', reason: 'as before, so that Reply/Forward can find it again');
      expect(image.attributes['width'], '80');
      expect(image.attributes['alt'], 'logo');
      expect(dio.calls, 0);
    });

    test('an image that declares its width and height gets the aspect ratio of the picture to come', () async {
      final html = await deferred(
        '<img src="cid:a" width="80" height="20">'
        '<img src="cid:b" width="80">'
        '<img src="cid:c" width="0" height="20">'
        '<img src="cid:d" width="80px" height="20px">'
        '<img src="cid:e" data-rf-ratio="1 / 1">',
      );

      final ratios = parse(html).querySelectorAll('img').map((img) => img.attributes[ImageTransformer.ratioAttribute]).toList();
      expect(ratios, ['80.0 / 20.0', null, null, null, null], reason: 'only two real numbers make a ratio; an email cannot bring its own');
    });

    test('markup of the email that imitates a placeholder is removed; other images are left alone', () async {
      final html = await deferred(
        '<img src="https://tracker.example/p.png" data-rf-cid="evil" data-rf-state="loaded">'
        '<img src="data:image/png;base64,AAAA" data-rf-state="pending">'
        '<img src="cid:real" data-rf-cid="evil" data-rf-state="loaded">',
      );

      final images = parse(html).querySelectorAll('img');
      expect(images[0].attributes.containsKey(ImageTransformer.cidAttribute), isFalse);
      expect(images[0].attributes.containsKey(ImageTransformer.stateAttribute), isFalse);
      expect(images[0].attributes['loading'], 'lazy');
      expect(images[1].attributes.containsKey(ImageTransformer.stateAttribute), isFalse);
      expect(images[1].attributes['src'], 'data:image/png;base64,AAAA');
      expect(images[2].attributes[ImageTransformer.cidAttribute], 'real');
      expect(images[2].attributes[ImageTransformer.stateAttribute], 'pending');
    });

    test('the transformer on its own (no sanitizer in front of it) removes the placeholder markup of the email, ratio included', () async {
      final document = parse(
        '<img src="https://tracker.example/p.png" data-rf-cid="evil" data-rf-state="loaded" data-rf-ratio="9 / 9">'
        '<img src="cid:real" data-rf-cid="evil" data-rf-state="loaded" data-rf-ratio="9 / 9">',
      );

      await const ImageTransformer(deferCidImages: true).process(document: document, dioClient: dio);

      final images = document.querySelectorAll('img');
      for (final forged in [ImageTransformer.cidAttribute, ImageTransformer.stateAttribute, ImageTransformer.ratioAttribute]) {
        expect(images[0].attributes.containsKey(forged), isFalse, reason: 'an image that is not a placeholder: $forged');
      }
      expect(images[1].attributes[ImageTransformer.cidAttribute], 'real');
      expect(images[1].attributes[ImageTransformer.stateAttribute], 'pending');
      expect(images[1].attributes.containsKey(ImageTransformer.ratioAttribute), isFalse, reason: 'the image declares no size, so no ratio');
      expect(dio.calls, 0);
    });

    test('the sanitizer still runs: script, event handlers and the like do not survive next to a placeholder', () async {
      final html = await deferred(
        '<p onclick="alert(1)">x</p><script>alert(2)</script><img src="cid:a" onerror="alert(3)">',
      );

      final document = parse(html);
      expect(document.querySelectorAll('script'), isEmpty);
      expect(html, isNot(contains('onclick')));
      expect(html, isNot(contains('onerror')));
      expect(document.querySelector('img')!.attributes[ImageTransformer.stateAttribute], 'pending');
    });

    test('a data: placeholder source is the only source of a pending image (no cid: left to be fetched by the browser)', () async {
      final html = await deferred('<img src="cid:a"><img src="cid:b">');

      for (final image in parse(html).querySelectorAll('img')) {
        expect(image.attributes['src'], startsWith('data:image/gif;base64,'));
      }
    });

    test('by default (not deferred) the picture is fetched and inlined as before, without any placeholder attribute', () async {
      final html = await htmlTransform.transformToHtml(
        htmlContent: '<img src="cid:a">',
        transformConfiguration: TransformConfiguration.forPreviewEmailOnWeb(),
        mapCidImageDownloadUrl: {'a': 'https://download.example.com/a'},
      );

      final image = parse(html).querySelector('img')!;
      expect(image.attributes['src'], startsWith('data:image/jpeg;base64,'));
      expect(image.attributes.containsKey(ImageTransformer.cidAttribute), isFalse);
      expect(dio.calls, 1);
    });
  });

  group('the swap into a placeholder::', () {
    test('only a base64 data: URI of png, jpeg, gif, webp or bmp is a source for a placeholder', () {
      for (final type in ['png', 'jpeg', 'gif', 'webp', 'bmp']) {
        expect(HtmlContentViewerOnWeb.isInlineImageSource('data:image/$type;base64,AAAA'), isTrue, reason: type);
        expect(HtmlContentViewerOnWeb.isInlineImageSource('data:image/$type;base64,AAAA=='), isTrue, reason: type);
      }
      for (final source in [
        'data:image/svg+xml;base64,AAAA',
        'data:image/svg+xml,<svg onload=alert(1)/>',
        'data:image/png,AAAA',
        'data:image/png;charset=utf-8,<script>',
        'data:text/html;base64,AAAA',
        'data:image/png;base64,',
        'data:image/png;base64,AA AA',
        'data:image/png;base64,AAAA"',
        'data:image/png;base64,AAAA\n',
        'data:image/PNG;base64,AAAA',
        'data:image/png;base64,AAAA===',
        ' data:image/png;base64,AAAA',
        'https://example.com/a.png',
        'javascript:alert(1)',
        'cid:a',
        '',
      ]) {
        expect(HtmlContentViewerOnWeb.isInlineImageSource(source), isFalse, reason: source);
      }
    });

    test('the script that does the swap: the same rule, matches by attribute value, sets src and state only', () {
      final script = HtmlInteraction.scriptsSwapInlineImages('view1234');

      expect(script, contains("var viewId = 'view1234';"));
      expect(script, contains('data.view !== viewId'), reason: 'strict match of the view id');
      expect(script, contains('(?:png|jpeg|gif|webp|bmp)'));
      expect(script, isNot(contains('svg')));
      expect(script, contains("getAttribute('data-rf-cid') === cid"), reason: 'no selector is built from the message');
      for (final risky in ['innerHTML', 'outerHTML', 'insertAdjacent', 'eval(', 'Function(', 'document.write', 'setAttribute(\'src\'', 'createElement', 'XMLHttpRequest', 'fetch(']) {
        expect(script, isNot(contains(risky)), reason: risky);
      }
      expect(script, contains('targets[i].src = data.src;'));
      expect(script, contains('!allowedSource.test(data.src)'), reason: 'the check is made before the src is set');
      expect(script, contains('if (ratio.test(wanted)) shaped[k].style.aspectRatio = wanted;'), reason: 'a ratio is applied only if it is two numbers');
      expect(script, contains("style.removeProperty('aspect-ratio')"), reason: 'the picture is not squeezed into the placeholder ratio');
    });

    test('the style sheet: a pending and a failed placeholder are a calm rounded neutral box, no animation', () {
      const css = HtmlTemplate.inlineImagePlaceholderCSS;

      expect(css, contains('img[data-rf-cid]:not([data-rf-state="loaded"])'));
      expect(css, contains('border-radius'));
      expect(css, contains('background-color'));
      expect(css, contains('img[data-rf-cid][data-rf-state="failed"]'));
      expect(css, contains('background-image'), reason: 'a failed image shows a picture glyph, not a broken-image icon');
      expect(css, contains(':not([width]):not([height])'), reason: 'an image that has its own size keeps it');
      expect(css, contains('aspect-ratio'));
      expect(css, isNot(contains('animation')));
      expect(css, isNot(contains('@keyframes')));
      expect(css, isNot(contains('transition')));
    });
  });
}
