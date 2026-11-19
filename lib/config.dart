import 'package:flutter/foundation.dart';

/// Shows developer tools (the test-notification buttons in Settings).
///
/// On in debug and profile builds ("LIT Dev"), off in the release app. To
/// turn them on in a release build, add `--dart-define=LIT_DEBUG_TOOLS=true`.
const bool showDebugTools = !kReleaseMode || bool.fromEnvironment('LIT_DEBUG_TOOLS');
