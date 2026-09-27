import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:live_cli/src/fixture/capture.dart';
import 'package:live_cli/src/fixture/rules.dart';
import 'package:live_cli/src/fixture/scrub.dart';

/// `live_cli fixture`: record redacted platform samples (ADR 0009).
class FixtureCommand extends Command<int> {
  /// Creates the command group.
  new() {
    addSubcommand(CaptureCommand());
  }

  @override
  String get name => 'fixture';

  @override
  String get description => 'Record redacted platform samples into fixtures/ (docs/adr/0009-fixture-format.md).';
}

/// `live_cli fixture capture <platform> <sample> --url ...`.
class CaptureCommand extends Command<int> {
  /// Creates the command.
  new() {
    argParser
      ..addOption('url', mandatory: true, help: 'Request URL.')
      ..addOption('method', defaultsTo: 'GET')
      ..addMultiOption('header', abbr: 'H', help: 'Request header "Name: value"; repeatable.', splitCommas: false)
      ..addOption('data', help: 'Request body (form or JSON).')
      ..addOption('cookie-file', help: 'File whose content is sent as the Cookie header (keeps it out of argv).')
      ..addOption('proxy', defaultsTo: 'direct', help: '"direct", "env" (HTTPS_PROXY) or host:port.')
      ..addOption('ext', help: 'Body file extension; guessed from Content-Type when omitted.')
      ..addOption('root', defaultsTo: '.', help: 'Repository root; samples go to <root>/fixtures/<platform>/<sample>/.')
      ..addFlag('allow-error', negatable: false, help: 'Keep non-2xx responses (error samples).');
  }

  @override
  String get name => 'capture';

  @override
  String get description => 'Fetch one URL, scrub it with the platform rules and write body + meta.json.';

  @override
  String get invocation => 'live_cli fixture capture <platform> <sample> --url <url> [options]';

  @override
  Future<int> run() async {
    final options = argResults!;
    if (options.rest.length != 2) usageException('Expected <platform> <sample>, for example: douyu S05-live');
    final [platform, sample] = options.rest;
    final rules = platformRules[platform];
    if (rules == null) usageException('No scrub rules for "$platform"; add them to lib/src/fixture/rules.dart first.');
    if (!RegExp(r'^S\d{2}[A-Za-z0-9-]*$').hasMatch(sample)) {
      usageException('Sample ids follow spec/sites/<platform>.md §11, for example S05-live.');
    }

    final headers = <String, String>{};
    for (final header in options.multiOption('header')) {
      final separator = header.indexOf(':');
      if (separator <= 0) usageException('Header must be "Name: value": $header');
      headers[header.substring(0, separator).trim()] = header.substring(separator + 1).trim();
    }
    final cookieFile = options.option('cookie-file');
    if (cookieFile != null) headers['Cookie'] = File(cookieFile).readAsStringSync().trim();

    final exchange = await fetch(
      CaptureRequest(
        url: Uri.parse(options.option('url')!),
        method: options.option('method')!.toUpperCase(),
        headers: headers,
        body: options.option('data'),
      ),
      proxy: options.option('proxy')!,
    );
    if ((exchange.status < 200 || exchange.status >= 300) && !options.flag('allow-error')) {
      stderr.writeln('HTTP ${exchange.status}; pass --allow-error to keep it as an error sample.');
      return 1;
    }

    final directory = Directory('${options.option('root')}/fixtures/$platform/$sample');
    try {
      final written = await writeSample(
        exchange,
        Scrubber(rules),
        directory: directory,
        platform: platform,
        sample: sample,
        extension: options.option('ext'),
        tool: 'live_cli fixture capture (schema $fixtureSchema)',
      );
      stdout.writeln(
        '${directory.path}: HTTP ${exchange.status}, ${exchange.body.length} bytes -> ${written.bodyFile}, '
        '${written.records.length} scrubbed location(s)',
      );
      return 0;
    } on LeakException catch (error) {
      stderr.writeln(error);
      return 3;
    }
  }
}
