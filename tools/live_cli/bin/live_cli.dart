import 'dart:io';

import 'package:args/command_runner.dart';

/// `dart run live_cli <command>`: real-network probes and sample recording.
///
/// The commands arrive with the platform adapters in phase 4; until then they
/// exit with code 2 so CI cannot mistake them for a passing probe.
Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<int>('live_cli', 'Pure Live v4 probes and sample recording.')
    ..addCommand(_PendingCommand('probe', 'Resolve a room through its adapter and read the first media packets.'))
    ..addCommand(_PendingCommand('record', 'Record redacted API samples into fixtures/.'))
    ..addCommand(_PendingCommand('danmaku', 'Connect to a room chat and print decoded messages.'))
    ..addCommand(_PendingCommand('lease', 'Follow a leased stream across renewals and report timestamp gaps.'));
  try {
    exitCode = await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  }
}

class _PendingCommand extends Command<int> {
  new(this.name, this.description);

  @override
  final String name;

  @override
  final String description;

  @override
  int run() {
    stderr.writeln('live_cli $name is not implemented yet (phase 4, docs/rewrite/STATUS.md).');
    return 2;
  }
}
