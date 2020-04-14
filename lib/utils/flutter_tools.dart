import 'dart:io';
import 'package:fvm/constants.dart';
import 'package:fvm/exceptions.dart';
import 'package:fvm/utils/helpers.dart';
import 'package:path/path.dart' as path;
import 'package:io/io.dart';
import 'package:fvm/utils/logger.dart';

/// Runs a process
Future<void> processRunner(String cmd, List<String> args, {String workingDirectory}) async {
  final manager = ProcessManager();

  try {
    var spawn = await manager.spawn(cmd, args, workingDirectory: workingDirectory);

    if (await spawn.exitCode != 0) {
      throw Exception('Could not run command $cmd: $args');
    }
    await sharedStdIn.terminate();
  } on Exception {
    rethrow;
  }
}

/// Clones Flutter SDK from Channel
/// Returns true if comes from exists or false if its new fetch.
Future<void> flutterChannelClone(String channel) async {
  final channelDirectory = Directory(path.join(kVersionsDir.path, channel));

  if (!isValidFlutterChannel(channel)) {
    throw ExceptionNotValidChannel('"$channel" is not a valid channel');
  }

  // If it's installed correctly just return and use cached
  if (await checkInstalledCorrectly(channel)) {
    return;
  }

  await channelDirectory.create(recursive: true);

  var result = await Process.run('git', ['clone', '-b', channel, kFlutterRepo, '.'], workingDirectory: channelDirectory.path);

  if (result.exitCode != 0) {
    throw ExceptionCouldNotClone('Could not clone $channel: ${result.stderr}');
  }
}

/// Check if Git is installed
Future<void> checkIfGitExists() async {
  try {
    await Process.run('git', ['--version']);
  } on ProcessException {
    throw Exception('You need Git Installed to run fvm. Go to https://git-scm.com/downloads');
  }
}

/// Clones Flutter SDK from Version Number
/// Returns exists:true if comes from cache or false if its new fetch.
Future<void> flutterVersionClone(String version) async {
  final versionDirectory = Directory(path.join(kVersionsDir.path, version));

  version = await coerceValidFlutterVersion(version);

  // If it's installed correctly just return and use cached
  if (await checkInstalledCorrectly(version)) {
    return;
  }

  await versionDirectory.create(recursive: true);

  var result = await Process.run('git', ['clone', '-b', version, kFlutterRepo, '.'], workingDirectory: versionDirectory.path);

  if (result.exitCode != 0) {
    throw ExceptionCouldNotClone('Could not clone $version: ${result.stderr}');
  }
}

/// Gets Flutter version from project
// Future<String> flutterGetProjectVersion() async {
//   final target = await kLocalFlutterLink.target();
//   print(target);
//   return await _gitGetVersion(target);
// }

/// Gets SDK Version
Future<String> flutterSdkVersion(String branch) async {
  final branchDirectory = Directory(path.join(kVersionsDir.path, branch));
  if (!await branchDirectory.exists()) {
    throw Exception('Could not get version from SDK that is not installed');
  }
  return await _gitGetVersion(branchDirectory.path);
}

Future<String> _gitGetVersion(String path) async {
  var result = await Process.run('git', ['rev-parse', '--abbrev-ref', 'HEAD'], workingDirectory: path);

  if (result.stdout.trim() == 'HEAD') {
    result = await Process.run('git', ['tag', '--points-at', 'HEAD'], workingDirectory: path);
  }

  if (result.exitCode != 0) {
    throw Exception('Could not get version Info.');
  }

  final versionNumber = result.stdout.trim() as String;
  return versionNumber;
}

/// Lists all Flutter SDK Versions
Future<List<String>> flutterListAllSdks() async {
  final result = await Process.run('git', ['ls-remote', '--tags', '$kFlutterRepo']);

  if (result.exitCode != 0) {
    throw Exception('Could not fetch list of available Flutter SDKs');
  }

  var tags = result.stdout.split('\n') as List<String>;

  var versionsList = <String>[];
  for (var tag in tags) {
    final version = tag.split('refs/tags/');

    if (version.length > 1) {
      versionsList.add(version[1]);
    }
  }

  return versionsList;
}

/// Removes a Version of Flutter SDK
Future<void> flutterSdkRemove(String version) async {
  final versionDir = Directory(path.join(kVersionsDir.path, version));
  if (await versionDir.exists()) {
    await versionDir.delete(recursive: true);
  }
}

/// Check if version is from git
Future<bool> checkInstalledCorrectly(String version) async {
  final versionDir = Directory(path.join(kVersionsDir.path, version));
  final gitDir = Directory(path.join(versionDir.path, '.github'));
  final flutterBin = Directory(path.join(versionDir.path, 'bin'));
  // Check if version directory exists
  if (!await versionDir.exists()) {
    return false;
  }

  // Check if version directory is from git
  if (!await gitDir.exists() || !await flutterBin.exists()) {
    logger.stdout('$version exists but was not setup correctly. Doing cleanup...');
    await flutterSdkRemove(version);
    return false;
  }

  return true;
}

/// Lists Installed Flutter SDK Version
Future<List<String>> flutterListInstalledSdks() async {
  try {
    // Returns empty array if directory does not exist
    if (!await kVersionsDir.exists()) {
      return [];
    }

    final versions = await kVersionsDir.list().toList();

    var installedVersions = <String>[];
    for (var version in versions) {
      if (await FileSystemEntity.type(version.path) == FileSystemEntityType.directory) {
        installedVersions.add(path.basename(version.path));
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
  final versionBin = Directory(path.join(kVersionsDir.path, version, 'bin', Platform.isWindows ? 'flutter.bat' : 'flutter'));
  await linkDir(kLocalFlutterLink, versionBin);
}
