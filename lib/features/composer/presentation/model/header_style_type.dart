
import 'package:flutter/material.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';

enum HeaderStyleType {
  normal,
  blockquote,
  code,
  h1,
  h2,
  h3,
  h4,
  h5,
  h6;

  String getStyleName(AppLocalizations appLocalizations) {
    switch (this) {
      case HeaderStyleType.normal:
        return appLocalizations.headerStyleNormal;
      case HeaderStyleType.blockquote:
        return appLocalizations.headerStyleQuote;
      case HeaderStyleType.code:
        return appLocalizations.headerStyleCode;
      case HeaderStyleType.h1:
        return appLocalizations.headerStyleHeading(1);
      case HeaderStyleType.h2:
        return appLocalizations.headerStyleHeading(2);
      case HeaderStyleType.h3:
        return appLocalizations.headerStyleHeading(3);
      case HeaderStyleType.h4:
        return appLocalizations.headerStyleHeading(4);
      case HeaderStyleType.h5:
        return appLocalizations.headerStyleHeading(5);
      case HeaderStyleType.h6:
        return appLocalizations.headerStyleHeading(6);
    }
  }

  String get styleValue {
    switch (this) {
      case HeaderStyleType.normal:
        return 'p';
      case HeaderStyleType.blockquote:
        return 'blockquote';
      case HeaderStyleType.code:
        return 'pre';
      case HeaderStyleType.h1:
        return 'h1';
      case HeaderStyleType.h2:
        return 'h2';
      case HeaderStyleType.h3:
        return 'h3';
      case HeaderStyleType.h4:
        return 'h4';
      case HeaderStyleType.h5:
        return 'h5';
      case HeaderStyleType.h6:
        return 'h6';
    }
  }

  String get summernoteNameAPI {
    switch (this) {
      case HeaderStyleType.normal:
        return 'formatPara';
      case HeaderStyleType.h1:
        return 'formatH1';
      case HeaderStyleType.h2:
        return 'formatH2';
      case HeaderStyleType.h3:
        return 'formatH3';
      case HeaderStyleType.h4:
        return 'formatH4';
      case HeaderStyleType.h5:
        return 'formatH5';
      case HeaderStyleType.h6:
        return 'formatH6';
      default:
        return '';
    }
  }

  double get textSize {
    switch(this) {
      case HeaderStyleType.normal:
        return 16;
      case HeaderStyleType.blockquote:
        return 16;
      case HeaderStyleType.code:
        return 13;
      case HeaderStyleType.h1:
        return 32;
      case HeaderStyleType.h2:
        return 24;
      case HeaderStyleType.h3:
        return 18;
      case HeaderStyleType.h4:
        return 16;
      case HeaderStyleType.h5:
        return 13;
      case HeaderStyleType.h6:
        return 11;
    }
  }

  FontWeight get fontWeight {
    switch(this) {
      case HeaderStyleType.normal:
      case HeaderStyleType.blockquote:
      case HeaderStyleType.code:
        return FontWeight.normal;
      case HeaderStyleType.h1:
      case HeaderStyleType.h2:
      case HeaderStyleType.h3:
      case HeaderStyleType.h4:
      case HeaderStyleType.h5:
      case HeaderStyleType.h6:
        return FontWeight.bold;
    }
  }
}