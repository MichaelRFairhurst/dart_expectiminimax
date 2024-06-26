import 'package:expectiminimax/src/engine.dart';
import 'package:expectiminimax/src/game.dart';
import 'package:expectiminimax/src/serve/serve_engine.dart';

/// Configuration for the [ServedEngine] class.
///
/// Currently only accepts a server string, such as 'localhost:8080'.
class ServedEngineConfig implements EngineConfig {
  /// The server URI hostname and/or port, e.g. 'localhost:8080'.
  final String server;

  ServedEngineConfig({required this.server});

  @override
  Engine<G> buildEngine<G extends Game<G>>() => ServedEngine(server);
}
