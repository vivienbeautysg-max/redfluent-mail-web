import 'dart:convert';
import 'dart:io';

import 'package:jmap_dart_client/jmap/mail/email/email.dart';

/// Layouts whose htmlBody has no non-text part and that name no photo by its Content-Location, so the email view
/// shows them as before (rf12). content_location is not among them since rf13 (its photo is drawn from its location).
const mimeUnchangedLayouts = [
  'apple_inline_pdf',
  'attachment_photo',
  'calendar_invite',
  'data_uri',
  'forwarded_rfc822',
  'gmail_inline',
  'mixed_inline_and_attachment',
  'orphan_cid',
  'outlook_signature',
];

/// The Email/get object the live Stalwart engine answered for a message (test/fixtures/mime/<key>.json, fetched
/// with fetchHTMLBodyValues and fetchTextBodyValues), with bodyValues cut to the htmlBody parts: the client asks
/// for fetchHTMLBodyValues only (EmailApi.getEmailContent).
Email loadMimeFixture(String key) {
  final json = jsonDecode(File('test/fixtures/mime/$key.json').readAsStringSync()) as Map<String, dynamic>;
  final htmlPartIds = {for (final part in json['htmlBody'] as List) (part as Map)['partId']};
  (json['bodyValues'] as Map).removeWhere((partId, _) => !htmlPartIds.contains(partId));
  return Email.fromJson(json);
}
