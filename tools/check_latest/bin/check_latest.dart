import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:check_latest/check_latest.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('root', defaultsTo: '.', help: 'Repository root containing toolchain.env and pubspec.lock.')
    ..addFlag('json', negatable: false, help: 'Print JSON instead of a Markdown table.')
    ..addFlag('report-only', negatable: false, help: 'Always exit 0, even when something is behind.')
    ..addFlag('skip-pub', negatable: false, help: 'Only check the toolchain and forks.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(parser.usage);
    exit(64);
  }
  if (options.flag('help')) {
    stdout
      ..writeln('Usage: dart run check_latest [options]')
      ..writeln(parser.usage);
    return;
  }

  final root = options.option('root')!;
  final env = readEnvFile(File('$root/toolchain.env').readAsStringSync());
  final lock = File('$root/pubspec.lock');
  final pub = options.flag('skip-pub') || !lock.existsSync()
      ? const <String, String>{}
      : readDirectHostedDependencies(lock.readAsStringSync());

  final findings = await collect(env: env, pub: pub);
  if (options.flag('json')) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(findings.map((f) => f.toJson()).toList()));
  } else {
    stdout.write(renderMarkdown(findings));
  }

  final behind = findings.where((f) => f.isBehind).length;
  final failed = findings.where((f) => f.latest.isEmpty).length;
  stderr.writeln('check_latest: ${findings.length} items, $behind behind, $failed lookups failed');
  if (!options.flag('report-only') && behind > 0) exit(1);
}
