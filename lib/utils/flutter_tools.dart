import 'dart:io';
import 'package:fvm/constants.dart';
import 'package:fvm/exceptions.dart';
import 'package:fvm/utils/helpers.dart';
import 'package:path/path.dart' as path;
import 'package:io/io.dart';
import 'package:git/git.dart';

/// Runs a process
Future<void> processRunner(String cmd, List<String> args,
    {String workingDirectory}) async {
  final manager = ProcessManager();

  try {
    var spawn =
        await manager.spawn(cmd, args, workingDirectory: workingDirectory);

    if (await spawn.exitCode != 0) {
      throw Exception('Could not run command $cmd: $args');
    }
    await sharedStdIn.terminate();
  } on Exception {
    rethrow;
  }
}

/// Returns true it's a valid installed version
Future<bool> isSdkInstalled(String version) async {
  return (await listInstalledSdks()).contains(version);
}

/// Returns true if it's a valid Flutter version number
Future<bool> isValidFlutterVersion(String version) async {
  if (kFlutterChannels.contains(version)) {
    return true;
  }
  return (await listAllRemoteTags()).contains('v$version');
}

/// Setup Local Version Worktree
Future<void> checkAndRunSetup() async {
  // Create directory if it doesn't exist
  if (await kVersionsDir.exists()) {
    await kVersionsDir.create(recursive: true);
  }

  // If its not a git directory clone it
  if (!await GitDir.isGitDir(kVersionsDir.path)) {
    var result = await Process.run('git', ['clone', kFlutterRepo, '.'],
        workingDirectory: kVersionsDir.path);

    if (result.exitCode != 0) {
      throw const ExceptionCouldNotClone(
          'Could no setup local Flutter Install');
    }
  }
}

/// Check if Git is installed
Future<void> checkIfGitExists() async {
  try {
    await Process.run('git', ['--version']);
  } on ProcessException {
    throw Exception(
        'You need Git Installed to run fvm. Go to https://git-scm.com/downloads');
  }
}

/// Clones Flutter SDK from Version Number or Channel
/// Returns exists:true if comes from cache or false if its new fetch.
Future<void> flutterVersionClone(String version) async {
  if (!await isValidFlutterVersion(version)) {
    throw ExceptionNotValidVersion(
        '"$version" is not a valid version or channel');
  }

  // Check if setup correctly if not do it.
  await checkAndRunSetup();

  // If it's master return
  if (version == 'master') {
    return;
  }

  // Add v in front of version name
  if (!kFlutterChannels.contains(version)) {
    version = 'v$version';
  }

  var result = await Process.run(
      'git', ['worktree', 'add', 'flutter-$version', version],
      workingDirectory: kVersionsDir.path);

  if (result.exitCode != 0) {
    throw ExceptionCouldNotClone('Could not clone $version: ${result.stderr}');
  }
}

/// Gets SDK Version
Future<String> getSDKVersion(String version) async {
  // Master is always the root version
  if (version == 'master') {
    version = '.';
  }
  final versionDir = Directory(path.join(kVersionsDir.path, version));

  if (!await versionDir.exists()) {
    throw Exception('Could not get version from SDK that is not installed');
  }
  return await _gitGetVersion(versionDir.path);
}

Future<String> _gitGetVersion(String path) async {
  var result = await Process.run('git', ['rev-parse', '--abbrev-ref', 'HEAD'],
      workingDirectory: path);

  if (result.stdout.trim() == 'HEAD') {
    result = await Process.run('git', ['tag', '--points-at', 'HEAD'],
        workingDirectory: path);
  }

  if (result.exitCode != 0) {
    throw Exception('Could not get version Info.');
  }

  final versionNumber = result.stdout.trim() as String;
  return versionNumber;
}

/// Lists all Flutter SDK Tags/Versions available for downoad
Future<List<String>> listAllRemoteTags() async {
  final result =
      await Process.run('git', ['ls-remote', '--tags', '$kFlutterRepo']);

  if (result.exitCode != 0) {
    throw Exception('Could not fetch list of available Flutter SDKs');
  }

  var tags = result.stdout.split('\n') as List<String>;

  var versionsList = <String>[];
  for (var tag in tags) {
    final version = tag.split('refs/tags/');

    // Add version name to the list
    if (version.length > 1) {
      versionsList.add(version[1]);
    }
  }

  return versionsList;
}

/// Removes a Version of Flutter SDK
Future<void> removeSdk(String version) async {
  if (version == 'master') {
    version = '.';
  }

  var result = await Process.run(
      'git', ['worktree', 'remove', 'flutter-$version'],
      workingDirectory: kVersionsDir.path);

  if (result.exitCode != 0) {
    throw Exception('Could not remove version');
  }
}

/// Lists Installed Flutter SDK Version
Future<List<String>> listInstalledSdks() async {
  try {
    await checkAndRunSetup();

    final result = await Process.run('git', ['worktree', 'list'],
        workingDirectory: kVersionsDir.path);

    if (result.exitCode != 0) {
      throw Exception('Could not list installed Flutter Sdks');
    }

    final versions = result.stdout.split('\n') as List<String>;

    var installedVersions = <String>[];

    for (var version in versions) {
      if (version.isNotEmpty) {
        const start = '[';
        const end = ']';
        final startIndex = version.indexOf(start);
        final endIndex = version.indexOf(end, startIndex + start.length);

        final versionName =
            version.substring(startIndex + start.length, endIndex);
        installedVersions.add(versionName);
      }
    }

    installedVersions.sort();

    return installedVersions;
  } on Exception {
    throw Exception('Could not list installed sdks');
  }
}

/// Links Flutter Dir to existsd SDK
Future<void> linkProjectFlutterDir(String version) async {
  final versionBin = Directory(path.join(kVersionsDir.path, version, 'bin',
      Platform.isWindows ? 'flutter.bat' : 'flutter'));
  await linkDir(kLocalFlutterLink, versionBin);
}
