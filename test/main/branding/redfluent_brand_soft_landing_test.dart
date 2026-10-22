import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:core/presentation/utils/responsive_utils.dart';
// crypto is a transitive dependency (jmap_dart_client & co); a test-only import does not justify a pubspec change
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmail_ui_user/features/base/widget/application_logo_with_text_widget.dart';
import 'package:tmail_ui_user/features/mailbox_dashboard/presentation/styles/navigation_bar_style.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations_delegate.dart';
import 'package:tmail_ui_user/main/localizations/localization_service.dart';

/// Redfluent Mail web, brand release: the "Soft Landing" brand (red dot on a line) replaces the old logo everywhere.
/// sha256 values are the ones in the brand package's READY.txt (2026-10-22); the files must be byte-identical.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const brandSha = <String, String>{
    'web/favicon.ico': '5ae087b8a22188f355b586ac6ab8b789ff561bdb7ce872ab4e53a3e4e503fcd5',
    'web/favicon.svg': 'dd7347122d0e29c028e40f73c830b076cb3b77c5eba684bd01dcc9602074c7b8',
    'web/favicon.png': '7c6752c307c8495ba6cc8debe5bd3414567b1fd415ec91dfeeb5120bcef6b0df',
    'web/apple-touch-icon.png': 'ebac612923026d48ab916fe4475a31116fbf1759c6a566177f45b73a3057097c',
    'web/icons/Icon-192.png': '57ed2f56720b1e89e067ded381453430a90fccc447cccf5a448622bf3bc01cc6',
    'web/icons/Icon-512.png': '0d08692ee24d7925f64e772137e774efe64f8433579d175b7c5e085f5270a792',
    'web/icons/Icon-maskable-192.png': 'c761814212e91d3620504206fab6728bee5b52211f9f79789edea698c9a225ee',
    'web/icons/Icon-maskable-512.png': 'd1dabd42b13eb3e54c5d0d20123d30d54945fc96651805e917f31a87fc2af4b1',
    'assets/images/redfluent_lockup_mail_light.svg': '2eb0ba547d44829aaf7acc92f53071102cb3a9a79a738162bd12357bd5f4b31d',
    'assets/images/redfluent_lockup_mail_dark.svg': 'f15de3ecd0d93ab94af344e4ff545c48e88fac8813e1686ea51b2ecdae8bfe41',
  };

  ({int w, int h, int colorType}) pngInfo(String path) {
    final b = ByteData.sublistView(Uint8List.fromList(File(path).readAsBytesSync().sublist(0, 26)));
    expect(b.getUint32(0), 0x89504E47, reason: '$path is not a PNG');
    return (w: b.getUint32(16), h: b.getUint32(20), colorType: b.getUint8(25));
  }

  group('brand files:', () {
    test('every icon / logo file is byte-identical to the brand package (sha256)', () {
      brandSha.forEach((path, sha) {
        expect(sha256.convert(File(path).readAsBytesSync()).toString(), sha, reason: path);
      });
    });

    test('the old logo files are gone', () {
      expect(File('assets/images/redfluent_logo_mark.png').existsSync(), isFalse);
      expect(File('web/splash/img/redfluent_logo.png').existsSync(), isFalse);
    });

    test('icon sizes: PWA 192/512 (any + maskable), apple-touch 180 opaque, favicon.png 128', () {
      expect(pngInfo('web/icons/Icon-192.png').w, 192);
      expect(pngInfo('web/icons/Icon-512.png').w, 512);
      expect(pngInfo('web/icons/Icon-maskable-192.png').w, 192);
      expect(pngInfo('web/icons/Icon-maskable-512.png').w, 512);
      final apple = pngInfo('web/apple-touch-icon.png');
      expect((apple.w, apple.h), (180, 180));
      expect(apple.colorType, 2, reason: 'iOS wants an opaque RGB icon (no alpha)');
      expect(pngInfo('web/favicon.png').w, 128);
    });

    test('the lockup SVGs have no text and no font (outlined), and the viewBox matches the widget aspect ratio', () {
      for (final f in ['light', 'dark']) {
        final svg = File('assets/images/redfluent_lockup_mail_$f.svg').readAsStringSync();
        expect(svg.contains('<text'), isFalse, reason: f);
        expect(svg.contains('font-family'), isFalse, reason: f);
        final vb = RegExp(r'viewBox="0 0 ([0-9.]+) ([0-9.]+)"').firstMatch(svg)!;
        expect(double.parse(vb.group(1)!) / double.parse(vb.group(2)!),
            closeTo(ApplicationLogoWidthTextWidget.lockupAspectRatio, 1e-6), reason: f);
      }
    });
  });

  group('web/index.html and manifest.json:', () {
    final index = File('web/index.html').readAsStringSync();
    final manifest = jsonDecode(File('web/manifest.json').readAsStringSync()) as Map<String, dynamic>;

    test('every local icon / image the page and the manifest point at exists', () {
      final refs = <String>{
        ...RegExp(r'<link rel="(?:icon|apple-touch-icon)"[^>]*href="([^"]+)"').allMatches(index).map((m) => m.group(1)!),
        ...RegExp(r'<img src="([^"]+)"').allMatches(index).map((m) => m.group(1)!),
        ...(manifest['icons'] as List).map((i) => (i as Map)['src'] as String),
      };
      expect(refs, containsAll(['favicon.ico', 'favicon.svg', 'apple-touch-icon.png']));
      for (final r in refs) {
        expect(File('web/$r').existsSync(), isTrue, reason: r);
      }
    });

    test('loading screen: inline animated mark, no image request, still mark for reduced motion, removed on first frame', () {
      expect(index.contains('<img src="splash/'), isFalse, reason: 'no splash image request any more');
      expect(index.contains('id="rf-splash"'), isTrue);
      // the brand loop: a 1.6 s landing (cy, d, opacity) once + a 1.8 s breath loop for the dot and the line
      final anim = index.substring(index.indexOf('class="rf-splash-anim"'), index.indexOf('class="rf-splash-static"'));
      expect('<animate '.allMatches(anim).length, 5);
      expect('repeatCount="indefinite"'.allMatches(anim).length, 2);
      expect(anim.contains('values="-24;46;68;55;60"'), isTrue);
      expect(anim.contains('fill="#C62A22"'), isTrue);
      expect(anim.contains('stroke="#141414"'), isTrue);
      // the still mark = the animation's final pose (mark-light.svg geometry)
      final still = index.substring(index.indexOf('class="rf-splash-static"'), index.indexOf('</div>', index.indexOf('class="rf-splash-static"')));
      expect(still.contains('<circle cx="60" cy="60" r="21" fill="#C62A22"/>'), isTrue);
      expect(still.contains('d="M6 70H30C41 70 43 83.5 60 83.5S79 70 90 70H114"'), isTrue);
      final css = File('web/splash/style.css').readAsStringSync();
      // the still mark is hidden by default and shown only under reduced motion (else both marks would stack)
      final hide = css.indexOf('#rf-splash .rf-splash-static { display: none; }');
      final media = css.indexOf('@media (prefers-reduced-motion: reduce)');
      expect(hide, greaterThan(-1));
      expect(media, greaterThan(hide), reason: 'the media block must come after the default rule to win');
      expect(css.substring(media).contains('#rf-splash .rf-splash-anim { display: none; }'), isTrue);
      expect(css.substring(media).contains('#rf-splash .rf-splash-static { display: block; }'), isTrue);
      // Flutter fires this on window after its first frame; without the listener the loop would run behind the app forever.
      // The listener must be registered BEFORE the bootstrap script (blocking scripts after it could delay it past the event).
      final listener = index.indexOf("addEventListener('flutter-first-frame'");
      expect(listener, greaterThan(-1));
      expect(listener, lessThan(index.indexOf('{{flutter_js}}')), reason: 'listener before the Flutter bootstrap script');
      expect(index.contains("getElementById('rf-splash')"), isTrue);
      expect(index.contains('splash.remove()'), isTrue);
    });

    test('no reference to the old logo files; title and names unchanged', () {
      expect(index.contains('redfluent_logo.png'), isFalse);
      expect(index.contains('href="favicon.png"'), isFalse);
      expect(index.contains('<title>Redfluent Mail</title>'), isTrue);
      expect(manifest['name'], 'Redfluent Mail');
      expect(manifest['short_name'], 'Redfluent Mail');
      // every HTML page of the web client names the product the same way in the tab
      for (final f in ['web/index.html', 'web/login-callback.html', 'web/logout-callback.html']) {
        expect(File(f).readAsStringSync().contains('<title>Redfluent Mail</title>'), isTrue, reason: f);
      }
    });

    test('manifest colours = white, the colour of the splash and of the first frame (scaffold Colors.white)', () {
      expect(manifest['theme_color'], '#FFFFFF');
      expect(manifest['background_color'], '#FFFFFF');
      expect(File('web/splash/style.css').readAsStringSync().contains('background-color: #ffffff'), isTrue);
    });

    test('UI primary colour is NOT changed by the brand release (still #0A66D8)', () {
      expect(File('core/lib/presentation/extensions/color_extension.dart').readAsStringSync().contains('0xFF0A66D8'), isTrue);
    });

    test('the manifest still lists 192/512 icons for "any" and for "maskable"', () {
      final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
      for (final size in ['192x192', '512x512']) {
        expect(icons.where((i) => i['sizes'] == size && i['purpose'] == null).length, 1, reason: 'any $size');
        expect(icons.where((i) => i['sizes'] == size && i['purpose'] == 'maskable').length, 1, reason: 'maskable $size');
      }
    });
  });

  group('ApplicationLogoWidthTextWidget:', () {
    Widget testApp(Widget body, {Brightness brightness = Brightness.light}) => MaterialApp(
          theme: ThemeData(brightness: brightness),
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: LocalizationService.supportedLocales,
          home: Scaffold(body: Align(alignment: Alignment.topLeft, child: body)),
        );

    Future<void> pump(WidgetTester tester, Brightness brightness, {double? iconSize, VoidCallback? onTap}) async {
      await tester.pumpWidget(testApp(ApplicationLogoWidthTextWidget(iconSize: iconSize, onTapAction: onTap), brightness: brightness));
      await tester.pump();
    }

    /// Paints the lockup on a light / dark surface and counts red, Ink-dark and Paper-light pixels: proves the SVG
    /// really parses and paints (not just that the right asset name is requested) and is legible on its surface.
    Future<({int red, int ink, int paper})> paintedPixels(WidgetTester tester, Brightness brightness) async {
      final key = GlobalKey();
      final surface = brightness == Brightness.dark ? const Color(0xFF0D0F1A) : Colors.white;
      await tester.pumpWidget(testApp(
        RepaintBoundary(key: key, child: ColoredBox(color: surface, child: const ApplicationLogoWidthTextWidget())),
        brightness: brightness,
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500))); // the asset loads on the real event loop
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      late ({int red, int ink, int paper}) counts;
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
        final image = await boundary.toImage(pixelRatio: 3);
        final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        var red = 0, ink = 0, paper = 0;
        for (var i = 0; i < data.length; i += 4) {
          final r = data[i], g = data[i + 1], b = data[i + 2];
          if (r > 170 && g < 80 && b < 70) {
            red++;
          } else if (r < 60 && g < 60 && b < 60 && surface == Colors.white) {
            ink++;
          } else if (r > 225 && g > 220 && b > 210) {
            paper++;
          }
        }
        image.dispose();
        counts = (red: red, ink: ink, paper: paper);
      });
      return counts;
    }

    String assetOf(WidgetTester tester) =>
        (tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader as SvgAssetLoader).assetName;

    testWidgets('light theme -> light lockup', (tester) async {
      await pump(tester, Brightness.light);
      expect(assetOf(tester), ApplicationLogoWidthTextWidget.lockupLightPath);
    });

    testWidgets('dark theme -> dark lockup', (tester) async {
      await pump(tester, Brightness.dark);
      expect(assetOf(tester), ApplicationLogoWidthTextWidget.lockupDarkPath);
    });

    testWidgets('size follows iconSize with the lockup aspect ratio (default 33, mobile app bar 22)', (tester) async {
      await pump(tester, Brightness.light);
      var size = tester.getSize(find.byType(SvgPicture));
      expect(size.height, closeTo(33 * ApplicationLogoWidthTextWidget.lockupHeightFactor, 1e-6));
      expect(size.width / size.height, closeTo(ApplicationLogoWidthTextWidget.lockupAspectRatio, 1e-6));
      await pump(tester, Brightness.light, iconSize: 22);
      size = tester.getSize(find.byType(SvgPicture));
      expect(size.height, closeTo(22 * ApplicationLogoWidthTextWidget.lockupHeightFactor, 1e-6));
    });

    test('the navigation bar lockup fits its leading slot (sidebar 236 - margin 30 = 206 px); the default size would not', () {
      const slot = ResponsiveUtils.sidebarMenuWidth - NavigationBarStyle.horizontalMargin;
      double widthAt(double iconSize) =>
          iconSize * ApplicationLogoWidthTextWidget.lockupHeightFactor * ApplicationLogoWidthTextWidget.lockupAspectRatio;
      expect(widthAt(ApplicationLogoWidthTextWidget.navigationBarIconSize), lessThanOrEqualTo(slot));
      expect(widthAt(33), greaterThan(slot), reason: 'if this stops being true the nav bar special size is not needed');
      expect(File('lib/features/mailbox_dashboard/presentation/widgets/navigation_bar/navigation_bar_widget.dart')
          .readAsStringSync()
          .contains('iconSize: ApplicationLogoWidthTextWidget.navigationBarIconSize'), isTrue);
    });

    testWidgets('screen readers get the product name; the old Image logo is not used', (tester) async {
      await pump(tester, Brightness.light);
      expect(tester.widget<SvgPicture>(find.byType(SvgPicture)).semanticsLabel, 'Redfluent Mail');
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('onTapAction still works (the nav bar logo goes to the inbox)', (tester) async {
      var taps = 0;
      await pump(tester, Brightness.light, onTap: () => taps++);
      await tester.tap(find.byType(SvgPicture));
      expect(taps, 1);
    });

    testWidgets('squeezed into a narrow slot it scales down instead of overflowing', (tester) async {
      await tester.pumpWidget(testApp(const SizedBox(width: 120, child: ApplicationLogoWidthTextWidget())));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(ApplicationLogoWidthTextWidget)).width, lessThanOrEqualTo(120 + 1e-6));
    });

    testWidgets('inside the nav bar\'s own Row (unbounded width) the nav bar size fits the 206 px slot, the default size overflows it',
        (tester) async {
      Future<void> slot(double? iconSize) => tester.pumpWidget(testApp(SizedBox(
            width: ResponsiveUtils.sidebarMenuWidth - NavigationBarStyle.horizontalMargin,
            child: Row(children: [ApplicationLogoWidthTextWidget(iconSize: iconSize), const Spacer()]),
          )));
      await slot(ApplicationLogoWidthTextWidget.navigationBarIconSize);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await slot(null); // negative control: this is the bug the nav bar size fixes (a 246 px lockup in a 206 px Row)
      await tester.pump();
      expect(tester.takeException(), isA<FlutterError>());
    });

    testWidgets('the mobile app bar size (22) fits a 320 px phone with both optional icons (32 padding + 2 x 40 + 36 spare)', (tester) async {
      await tester.pumpWidget(testApp(const SizedBox(
        width: 320,
        child: Row(children: [
          ApplicationLogoWidthTextWidget(iconSize: 22),
          Spacer(),
          SizedBox(width: 40, height: 40),
          SizedBox(width: 40, height: 40),
          SizedBox(width: 32),
        ]),
      )));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the light lockup really paints on a light surface: red dot + Ink line and wordmark', (tester) async {
      final c = await paintedPixels(tester, Brightness.light);
      expect(c.red, greaterThan(200), reason: 'the red dot');
      expect(c.ink, greaterThan(1500), reason: 'Ink wordmark + line on white');
    });

    testWidgets('the dark lockup really paints on a dark surface: red dot + Paper line and wordmark (legible, not Ink on dark)', (tester) async {
      final c = await paintedPixels(tester, Brightness.dark);
      expect(c.red, greaterThan(200), reason: 'the red dot');
      expect(c.paper, greaterThan(1500), reason: 'Paper wordmark + line on dark');
    });
  });
}
