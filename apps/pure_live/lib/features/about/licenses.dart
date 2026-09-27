import 'package:flutter/foundation.dart';

bool _registered = false;

/// Adds the app's own licence and the native libraries' to the licence page
/// (ADR 0006: the page is generated; Flutter collects every Dart package's
/// LICENSE file, these entries cover what is not a Dart package).
void registerAppLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['纯粹直播 Pure Live'],
      'Copyright (C) the Pure Live authors.\n\n'
      'This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero '
      'General Public License as published by the Free Software Foundation, either version 3 of the License, or '
      '(at your option) any later version.\n\n'
      'This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the '
      'implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public '
      'License for more details: https://www.gnu.org/licenses/agpl-3.0.html\n\n'
      'Source code: https://github.com/wzgrx/pure_live',
    );
    yield const LicenseEntryWithLineBreaks(
      ['libmpv', 'FFmpeg', 'libplacebo', 'dav1d', 'mbedtls'],
      'The player uses libmpv and FFmpeg built with --enable-version3 (LGPL-3.0-or-later) and their dependencies '
      'under their own licences. Every release ships the corresponding source archive of these native libraries '
      '(upstream commits, build options and patches) next to the app packages: '
      'https://github.com/wzgrx/pure_live/releases',
    );
  });
}
