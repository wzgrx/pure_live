import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:live_cli/live_cli.dart';

/// `dart run live_cli <command>`: real-network probes and sample recording.
///
/// `fixture` records samples (phase 1), `probe` checks an adapter end to end
/// and `lease` follows a leased stream through the v4 relay. `danmaku` arrives
/// with live_danmaku; until then it exits with code 2 so CI cannot mistake it
/// for a passing probe.
Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<int>('live_cli', 'Pure Live v4 probes and sample recording.')
    ..addCommand(ProbeCommand())
    ..addCommand(FixtureCommand())
    ..addCommand(_PendingCommand('danmaku', 'Connect to a room chat and print decoded messages.'))
    ..addCommand(LeaseCommand());
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
