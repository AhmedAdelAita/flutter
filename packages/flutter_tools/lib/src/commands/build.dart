// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

import '../build_info.dart';
import '../commands/build_linux.dart';
import '../commands/build_macos.dart';
import '../commands/build_windows.dart';
import '../globals.dart' as globals;
import '../runner/flutter_command.dart';
import 'build_aar.dart';
import 'build_apk.dart';
import 'build_appbundle.dart';
import 'build_bundle.dart';
import 'build_ios.dart';
import 'build_ios_framework.dart';
import 'build_macos_framework.dart';
import 'build_web.dart';

class BuildCommand extends FlutterCommand {
  BuildCommand({ bool verboseHelp = false }) {
    _addSubcommand(BuildAarCommand(verboseHelp: verboseHelp));
    _addSubcommand(BuildApkCommand(verboseHelp: verboseHelp));
    _addSubcommand(BuildAppBundleCommand(verboseHelp: verboseHelp));
    _addSubcommand(BuildIOSCommand(verboseHelp: verboseHelp));
    _addSubcommand(BuildIOSFrameworkCommand(
      buildSystem: globals.buildSystem,
      verboseHelp: verboseHelp,
    ));
    _addSubcommand(BuildMacOSFrameworkCommand(
      buildSystem: globals.buildSystem,
      verboseHelp: verboseHelp,
    ));
    _addSubcommand(BuildIOSArchiveCommand(verboseHelp: verboseHelp));
    _addSubcommand(BuildBundleCommand(verboseHelp: verboseHelp));
    _addSubcommand(BuildWebCommand(verboseHelp: verboseHelp));
    _addSubcommand(BuildMacosCommand(verboseHelp: verboseHelp));
    _addSubcommand(BuildLinuxCommand(
      operatingSystemUtils: globals.os,
      verboseHelp: verboseHelp
    ));
    _addSubcommand(BuildWindowsCommand(verboseHelp: verboseHelp));
  }

  void _addSubcommand(BuildSubCommand command) {
    if (command.supported) {
      addSubcommand(command);
    }
  }

  @override
  final String name = 'build';

  @override
  final String description = 'Build an executable app or install bundle.';

  @override
  String get category => FlutterCommandCategory.project;

  @override
  Future<FlutterCommandResult> runCommand() async => FlutterCommandResult.fail();
}

abstract class BuildSubCommand extends FlutterCommand {
  BuildSubCommand({required bool verboseHelp}) {
    requiresPubspecYaml();
    usesFatalWarningsOption(verboseHelp: verboseHelp);
  }

  @override
  bool get reportNullSafety => true;

  bool get supported => true;

  /// Display a message describing the current null safety runtime mode
  /// that was selected.
  ///
  /// This is similar to the run message in run_hot.dart
  @protected
  void displayNullSafetyMode(BuildInfo buildInfo) {
    globals.printStatus('');
    if (buildInfo.nullSafetyMode == NullSafetyMode.sound) {
      globals.printStatus(
        '💪 Building with sound null safety 💪',
        emphasis: true,
      );
    } else {
      globals.printStatus(
        'Building without sound null safety ⚠️',
        emphasis: true,
      );
      globals.printStatus(
        'Dart 3 will only support sound null safety, see https://dart.dev/null-safety',
      );
    }
    globals.printStatus('');
  }
}
