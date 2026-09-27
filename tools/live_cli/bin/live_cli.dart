import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:live_cli/live_cli.dart';

/// `dart run live_cli <command>`: real-network probes and sample recording.
///
/// `fixture` records HTTP samples, `probe` checks an adapter end to end,
/// `lease` follows a leased stream through the v4 relay, `danmaku` joins a
/// room chat (and records its frames) and `record` records a room with the v4
/// recorder and checks the files.
Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<int>('live_cli', 'Pure Live v4 probes and sample recording.')
    ..addCommand(ProbeCommand())
    ..addCommand(FixtureCommand())
    ..addCommand(DanmakuCommand())
    ..addCommand(LeaseCommand())
    ..addCommand(RecordCommand());
  try {
    exitCode = await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  }
}
