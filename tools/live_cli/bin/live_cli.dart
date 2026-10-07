import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:live_cli/live_cli.dart';

/// `dart run tools/live_cli/bin/live_cli.dart <command>`: real-network
/// checks of the platform adapters. `probe` follows one room from link to
/// media bytes; `patrol` runs the checks of
/// docs/E-直播平台/E07-平台巡检/CHECKS.md and writes a report.
///
/// Exit codes: 0 all normal or unsupported, 1 a check failed, 64 bad usage.
Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<int>('live_cli', 'Pure Live platform probe and patrol.')
    ..addCommand(ProbeCommand())
    ..addCommand(PatrolCommand());
  try {
    exitCode = await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  }
  // A connection still in its TLS handshake after a timeout would keep the
  // VM alive until the OS gives up; the command is done, so leave.
  await stdout.flush();
  await stderr.flush();
  exit(exitCode);
}
