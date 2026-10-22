import 'dart:convert' show HtmlEscape;

import 'package:html/parser.dart' show parse;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_body_part.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_body_value.dart';
import 'package:model/email/attachment.dart';
import 'package:model/extensions/email_extension.dart';
import 'package:model/extensions/list_attachment_extension.dart';
import 'package:model/extensions/list_email_content_extension.dart';

class PresentationAttachments {
  final List<Attachment> attachments;
  final List<Attachment> inlineImages;

  const PresentationAttachments({
    required this.attachments,
    required this.inlineImages,
  });
}

extension EmailAttachmentClassifierExtension on Email {
  PresentationAttachments toPresentationAttachments() {
    // Cache: allAttachments getter re-allocates on each call.
    final allAttachmentsSnapshot = allAttachments;
    final outsideAttachments = allAttachmentsSnapshot.getListAttachmentsDisplayedOutside(htmlBodyAttachments);
    final allInlineImages = allAttachmentsSnapshot.listAttachmentsDisplayedInContent;
    final referencedCids = _extractReferencedCids(emailContentList.asHtmlString);
    final inlineImages = <Attachment>[];
    final orphanedInlineImages = <Attachment>[];
    for (final a in allInlineImages) {
      (referencedCids.contains(a.cid) ? inlineImages : orphanedInlineImages).add(a);
    }
    // Dedupe: undefined-disposition + cid attachments satisfy both
    // isOutsideAttachment and listAttachmentsDisplayedInContent predicates.
    // Without this filter the same blob would render twice in the panel.
    // nonNulls: a null blobId in the orphan set would otherwise falsely match
    // any outside attachment with a null blobId (Set<Id?> collapses all nulls).
    final orphanBlobIds = orphanedInlineImages.map((a) => a.blobId).nonNulls.toSet();
    final outsideOnly = outsideAttachments
      .where((a) => a.blobId == null || !orphanBlobIds.contains(a.blobId))
      .toList();
    return PresentationAttachments(
      attachments: [...outsideOnly, ...orphanedInlineImages],
      inlineImages: inlineImages,
    );
  }

  /// For the email view only (the composer keeps the email as fetched). Mail apps (Apple Mail, iPhone) put a
  /// photo in the body as an `image/*` part without Content-ID. JMAP lists it in htmlBody, so the attachment
  /// panel skips it, and the inline-image path needs a cid, so it is shown nowhere. This returns a copy in which
  /// such a photo (a type a browser draws) is a text/html part `<img src="cid:rf-photo-...">` at its position in
  /// htmlBody and an inline attachment with that cid, which the existing cid -> download URL path renders. Any
  /// other non-text part without cid (HEIC, SVG, video, ...) leaves htmlBody, so the panel lists it as an
  /// attachment (and is added to attachments if the server did not list it there). An email with no such part
  /// is returned as it is.
  Email withInlinePhotos() {
    final bodyParts = htmlBody;
    if (bodyParts == null || !bodyParts.any(_isMediaWithoutCid)) return this;
    final newHtmlBody = <EmailBodyPart>{};
    final newBodyValues = <PartId, EmailBodyValue>{};
    final photos = <EmailBodyPart>[];
    final notInlined = <EmailBodyPart>[];
    for (final part in bodyParts) {
      if (!_isMediaWithoutCid(part)) {
        newHtmlBody.add(part);
        final value = bodyValues?[part.partId];
        if (value != null) newBodyValues[part.partId!] = value;
      } else if (_isInlinePhoto(part)) {
        final cid = 'rf-photo-${part.partId!.value}-${part.blobId!.value}';
        final imgPartId = PartId(cid);
        newHtmlBody.add(EmailBodyPart(partId: imgPartId, type: MediaType('text', 'html')));
        newBodyValues[imgPartId] = EmailBodyValue(
          value: _imgTag(cid, part),
          isEncodingProblem: false,
          isTruncated: false,
        );
        photos.add(EmailBodyPart(
          partId: part.partId,
          blobId: part.blobId,
          size: part.size,
          name: part.name,
          type: part.type,
          charset: part.charset,
          disposition: ContentDisposition.inline.name,
          cid: cid,
          location: part.location,
        ));
      } else {
        notInlined.add(part);
      }
    }
    final photoPartIds = photos.map((photo) => photo.partId).toSet();
    final attachmentPartIds = attachments?.map((part) => part.partId).toSet() ?? {};
    return copyWith(
      htmlBody: newHtmlBody,
      bodyValues: newBodyValues,
      attachments: {
        ...?attachments?.where((part) => !photoPartIds.contains(part.partId)),
        ...photos,
        // the server lists them in attachments as well; if one does not, they must not be lost
        ...notInlined.where((part) => !attachmentPartIds.contains(part.partId)),
      },
    );
  }
}

// What a browser draws in an <img>. HEIC/HEIF/TIFF it cannot draw, SVG can carry script: those stay attachments.
const _inlinePhotoTypes = {
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
};

bool _isMediaWithoutCid(EmailBodyPart part) =>
    part.partId != null &&
    part.type != null &&
    part.type!.type != 'text' &&
    (part.cid?.isEmpty ?? true);

bool _isInlinePhoto(EmailBodyPart part) =>
    part.blobId != null &&
    part.disposition.toContentDisposition() != ContentDisposition.attachment &&
    _inlinePhotoTypes.contains(part.type!.mimeType);

String _imgTag(String cid, EmailBodyPart photo) {
  final name = photo.name;
  final alt = name == null || name.isEmpty
      ? ''
      : ' alt="${const HtmlEscape().convert(name)}"';
  return '<div><img src="cid:$cid" data-mimetype="${photo.type!.mimeType}"$alt '
      'style="max-width:100%;height:auto"></div>';
}

Set<String> _extractReferencedCids(String htmlContent) {
  if (htmlContent.isEmpty) return {};
  try {
    return parse(htmlContent)
      .querySelectorAll('img[src^="cid:"]')
      .map((img) => img.attributes['src']?.substring('cid:'.length).trim())
      .nonNulls
      .toSet();
  } catch (_) {
    return {};
  }
}
