// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import '../artifacts.dart';
import '../base/common.dart';
import '../base/file_system.dart';
import '../base/logger.dart';
import '../base/process.dart';
import '../build_info.dart';
import '../cache.dart';
import '../globals.dart' as globals;
import '../plugins.dart';
import '../project.dart';
import 'property_sheet.dart';
import 'visual_studio.dart';

/// Builds the Windows project using msbuild.
Future<void> buildWindows(WindowsProject windowsProject, BuildInfo buildInfo, {String target}) async {
  if (!windowsProject.solutionFile.existsSync()) {
    throwToolExit(
      'No Windows desktop project configured. '
      'See https://github.com/flutter/flutter/wiki/Desktop-shells#create '
      'to learn about adding Windows support to a project.');
  }

  // Ensure that necessary emphemeral files are generated and up to date.
  _writeGeneratedFlutterProperties(windowsProject, buildInfo, target);
  createPluginSymlinks(windowsProject.project);

  final String vcvarsScript = visualStudio.vcvarsPath;
  if (vcvarsScript == null) {
    throwToolExit('Unable to find suitable Visual Studio toolchain. '
        'Please run `flutter doctor` for more details.');
  }

  if (!buildInfo.isDebug) {
    const String warning = '🚧 ';
    globals.printStatus(warning * 20);
    globals.printStatus('Warning: Only debug is currently implemented for Windows. This is effectively a debug build.');
    globals.printStatus('See https://github.com/flutter/flutter/issues/38477 for details and updates.');
    globals.printStatus(warning * 20);
    globals.printStatus('');
  }

  final String buildScript = globals.fs.path.join(
    Cache.flutterRoot,
    'packages',
    'flutter_tools',
    'bin',
    'vs_build.bat',
  );

  final String configuration = buildInfo.isDebug ? 'Debug' : 'Release';
  final String solutionPath = windowsProject.solutionFile.path;
  final Stopwatch sw = Stopwatch()..start();
  final Status status = globals.logger.startProgress(
    'Building Windows application...',
    timeout: null,
  );
  int result;
  try {
    // Run the script with a relative path to the project using the enclosing
    // directory as the workingDirectory, to avoid hitting the limit on command
    // lengths in batch scripts if the absolute path to the project is long.
    result = await processUtils.stream(<String>[
      buildScript,
      vcvarsScript,
      globals.fs.path.basename(solutionPath),
      configuration,
    ], workingDirectory: globals.fs.path.dirname(solutionPath), trace: true);
  } finally {
    status.cancel();
  }
  if (result != 0) {
    throwToolExit('Build process failed. To view the stack trace, please run `flutter run -d windows -v`.');
  }
  globals.flutterUsage.sendTiming('build', 'vs_build', Duration(milliseconds: sw.elapsedMilliseconds));
}

/// Writes the generatedPropertySheetFile with the configuration for the given build.
void _writeGeneratedFlutterProperties(WindowsProject windowsProject, BuildInfo buildInfo, String target) {
  final Map<String, String> environment = <String, String>{
    'FLUTTER_ROOT': Cache.flutterRoot,
    'FLUTTER_EPHEMERAL_DIR': windowsProject.ephemeralDirectory.path,
    'PROJECT_DIR': windowsProject.project.directory.path,
    'TRACK_WIDGET_CREATION': (buildInfo?.trackWidgetCreation == true).toString(),
  };
  if (target != null) {
    environment['FLUTTER_TARGET'] = target;
  }
  if (globals.artifacts is LocalEngineArtifacts) {
    final LocalEngineArtifacts localEngineArtifacts = globals.artifacts as LocalEngineArtifacts;
    final String engineOutPath = localEngineArtifacts.engineOutPath;
    environment['FLUTTER_ENGINE'] = globals.fs.path.dirname(globals.fs.path.dirname(engineOutPath));
    environment['LOCAL_ENGINE'] = globals.fs.path.basename(engineOutPath);
  }

  final File propsFile = windowsProject.generatedPropertySheetFile;
  propsFile.createSync(recursive: true);
  propsFile.writeAsStringSync(PropertySheet(environmentVariables: environment).toString());
}
