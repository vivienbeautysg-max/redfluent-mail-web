import 'package:core/presentation/utils/html_transformer/dom/image_transformers.dart';
import 'package:equatable/equatable.dart';
import 'package:html/parser.dart' show parse;
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:model/email/attachment.dart';
import 'package:tmail_ui_user/features/email/presentation/extensions/email_extension.dart';
import 'package:tmail_ui_user/features/email/presentation/model/smime_signature_status.dart';

/// [EmailLoaded.htmlContent] for an HTML with inline-image placeholders (see [ImageTransformer.cidAttribute]): the
/// pictures in [sources] are inlined as data: URIs, any other placeholder becomes its `cid:` source again (the
/// composer attaches such an image by its cid). An HTML without placeholders is returned as it is.
String resolveInlineImagePlaceholders(String html, Map<String, String> sources) {
  if (!html.contains(ImageTransformer.cidAttribute)) return html;
  final document = parse(html);
  for (final image in document.querySelectorAll('img[${ImageTransformer.cidAttribute}]')) {
    final cid = image.attributes.remove(ImageTransformer.cidAttribute) ?? '';
    image.attributes.remove(ImageTransformer.stateAttribute);
    image.attributes.remove(ImageTransformer.ratioAttribute);
    image.attributes['src'] = sources[cid] ?? 'cid:$cid';
  }
  return document.outerHtml;
}

class EmailLoaded with EquatableMixin {
  /// What the email view shows: inline images that are still being fetched are placeholders.
  final String displayHtml;

  /// The pictures of the placeholders that have arrived (cid -> data: URI) and the cids that could not be fetched.
  final Map<String, String> inlineImageSources;
  final Set<String> failedInlineImages;
  final List<Attachment> attachments;
  final List<Attachment> inlineImages;
  final Email? emailCurrent;

  /// The email's HTML for Reply, Forward and print: the pictures that have arrived are inlined, an image that is
  /// still loading or failed is a `cid:` source again. Equal to [displayHtml] when it has no placeholders.
  late final String htmlContent = resolveInlineImagePlaceholders(displayHtml, inlineImageSources);

  EmailLoaded({
    required String htmlContent,
    required this.attachments,
    required this.inlineImages,
    this.emailCurrent,
    this.inlineImageSources = const {},
    this.failedInlineImages = const {},
  }) : displayHtml = htmlContent;

  /// Some placeholder of [displayHtml] has neither received its picture nor failed.
  bool get hasPendingInlineImages =>
      displayHtml.contains(ImageTransformer.cidAttribute) &&
      inlineImages.any((image) =>
          image.hasCid() &&
          !inlineImageSources.containsKey(image.cid) &&
          !failedInlineImages.contains(image.cid));

  EmailLoaded copyWith({
    String? htmlContent,
    List<Attachment>? attachments,
    List<Attachment>? inlineImages,
    Email? emailCurrent,
    Map<String, String>? inlineImageSources,
    Set<String>? failedInlineImages,
  }) {
    return EmailLoaded(
      htmlContent: htmlContent ?? displayHtml,
      attachments: attachments ?? this.attachments,
      inlineImages: inlineImages ?? this.inlineImages,
      emailCurrent: emailCurrent ?? this.emailCurrent,
      inlineImageSources: inlineImageSources ?? this.inlineImageSources,
      failedInlineImages: failedInlineImages ?? this.failedInlineImages,
    );
  }

  SMimeSignatureStatus? get sMimeStatus => emailCurrent?.sMimeStatus;

  @override
  List<Object?> get props => [
    displayHtml,
    attachments,
    inlineImages,
    emailCurrent,
    inlineImageSources.keys.toList(),
    failedInlineImages,
  ];
}
