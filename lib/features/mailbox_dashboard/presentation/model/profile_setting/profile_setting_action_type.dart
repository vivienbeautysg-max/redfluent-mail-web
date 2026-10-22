
import 'package:core/presentation/resources/image_paths.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';

enum ProfileSettingActionType {
  manageAccount,
  setupGuide,
  signOut;

  String getTitle(AppLocalizations appLocalizations) {
    switch(this) {
      case ProfileSettingActionType.manageAccount:
        return appLocalizations.manage_account;
      case ProfileSettingActionType.setupGuide:
        return appLocalizations.setupGuide;
      case ProfileSettingActionType.signOut:
        return appLocalizations.sign_out;
    }
  }

  String getIcon(ImagePaths imagePaths) {
    switch(this) {
      case ProfileSettingActionType.manageAccount:
        return imagePaths.icSetting;
      case ProfileSettingActionType.setupGuide:
        return imagePaths.icPhoneSetup;
      case ProfileSettingActionType.signOut:
        return imagePaths.icLogout;
    }
  }

  String? getKey() {
    return switch (this) {
      ProfileSettingActionType.manageAccount => name,
      ProfileSettingActionType.setupGuide => name,
      _ => null,
    };
  }
}