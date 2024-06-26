import 'dart:math';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:expectiminimax/src/engine.dart';
import 'package:expectiminimax/src/mcts.dart';
import 'package:expectiminimax/src/other_engines/nth_engine.dart';
import 'package:expectiminimax/src/other_engines/random_engine.dart';
import 'package:expectiminimax/src/serve/serve_command.dart';
import 'package:expectiminimax/src/serve/served_engine_config.dart';
import 'package:thread/thread.dart';
import 'package:expectiminimax/src/config.dart';
import 'package:expectiminimax/src/elo.dart';
import 'package:expectiminimax/src/game.dart';
import 'package:expectiminimax/src/move.dart';
import 'package:expectiminimax/src/perft.dart';

class CliTools<G extends Game<G>> {
  final G startingGame;
  final G Function(String) decoder;
  final ExpectiminimaxConfig defaultXmmConfig;
  final MctsConfig defaultMctsConfig;

  CliTools({
    required this.startingGame,
    required this.defaultXmmConfig,
    required this.defaultMctsConfig,
    G Function(String)? decoder,
  }) : decoder = decoder ?? throwingDecoder;

  static Never throwingDecoder(String) =>
      throw UnimplementedError('no decoder specified');

  void run(List<String> args) {
    // Convert args to a mutable list
    args = args.toList();

    // Split args by '--vs' into sections
    final sections = <List<String>>[];

    while (true) {
      final index = args.indexOf('--vs');
      if (index == -1) {
        sections.add(args);
        break;
      }

      final section = args.getRange(0, index);
      sections.add(section.toList());
      args.removeRange(0, index + 1);
    }

    final configs = sections.skip(1).toList();

    final commandRunner = ListEnginesCommandRunner('dart your_wrapper.dart',
        'Pre-built CLI tools to run expectiminimax on custom games')
      ..addCommand(PerftCommand(startingGame))
      // TODO: play two AIs against each other
      ..addCommand(
          WatchGame(startingGame, defaultXmmConfig, defaultMctsConfig, []))
      // TODO: Distinguish SingleConfigCommand from MultiConfigCommand
      ..addCommand(
          Benchmark(startingGame, defaultXmmConfig, defaultMctsConfig, []))
      ..addCommand(
          Compare(startingGame, defaultXmmConfig, defaultMctsConfig, configs))
      ..addCommand(
          Rank(startingGame, defaultXmmConfig, defaultMctsConfig, configs))
      ..addCommand(
          ServeCommand(decoder, defaultXmmConfig, defaultMctsConfig, configs));

    // Workaround: parse command separately before running it. Command Runner
    // does not like our usage of subcommands and crashes on run() if there's a
    // parse error. This parse() call correctly throws.
    commandRunner.argParser.parse(sections[0]);

    // If we didn't throw, we can safely run.
    commandRunner.run(sections[0]);
  }
}

class ListEnginesCommandRunner extends CommandRunner {
  ListEnginesCommandRunner(super.name, super.description);

  @override
  String get usageFooter => '''

Available engines for the above commands:
  xmm       Expectiminimax engine.
  mcts      Monte-Carlo Tree Search engine.
  served    Connect over API to engine hosted by `serve` command.
  random    Utility engine which simply picks a random move.
  nth       Utility engine which always picks the nth move or nth-to-last move.
''';
}

class WatchGame<G extends Game<G>> extends ParseConfigCommand {
  final name = 'watch';
  final description = 'Run a game and print out the moves/events/positions.';

  final G startingGame;

  WatchGame(this.startingGame, ExpectiminimaxConfig defaultXmmConfig,
      MctsConfig defaultMctsConfig, List<List<String>> configSpecs)
      : super(defaultXmmConfig, defaultMctsConfig, configSpecs) {
    argParser.addOption('seed',
        abbr: 's', help: 'Random number generator seed.');
    argParser.addOption('print-stats',
        abbr: 'p',
        help: 'Which stats to print (if any) when the game is finished.',
        allowed: const ['time', 'all', 'none'],
        defaultsTo: 'time');
    argParser.addFlag('print-timing',
        help: 'Print timing when the game is finished.');
  }

  @override
  void runWithConfigs(List<EngineConfig> configs) async {
    final config = configs[0];
    final printStats = argResults!['print-stats'];
    final seed =
        argResults!['seed'] == null ? null : int.parse(argResults!['seed']);

    final random = Random(seed);
    var engine = config.buildEngine<G>();
    var game = startingGame;
    var steps = 0;
    while (game.score != 1.0 && game.score != -1.0) {
      steps++;
      print('step $steps');
      final move = await engine.chooseBest(game.getMoves(), game);
      print('Player chooses: ${move.description}');
      final chance = move.perform(game);
      final outcome = chance.pick(random.nextDouble());
      print('random event: ${outcome.description}');
      game = outcome.outcome;
      print('new game state:');
      print(game);
      print('');
    }

    print('');
    print('GAME OVER!');
    print('');

    if (printStats == 'all') {
      print('steps $steps');
      print(engine.stats);
    } else if (printStats == 'time') {
      print('took ${engine.stats.duration.inMilliseconds}ms');
    }
  }
}

class Benchmark<G extends Game<G>> extends ParseConfigCommand {
  final name = 'bench';
  final description = 'Play a series of games, tracking performance.';

  final G startingGame;

  Benchmark(this.startingGame, ExpectiminimaxConfig defaultXmmConfig,
      MctsConfig defaultMctsConfig, List<List<String>> configSpecs)
      : super(defaultXmmConfig, defaultMctsConfig, configSpecs) {
    argParser.addOption('count',
        abbr: 'c', defaultsTo: '20', help: 'How many games to play');
    argParser.addOption('seed',
        abbr: 's', help: 'Random number generator seed.');
    argParser.addFlag('refresh',
        abbr: 'r',
        help: 'Whether or not to clear cache results between games',
        defaultsTo: false);
  }

  @override
  void runWithConfigs(List<EngineConfig> configs) async {
    final seed =
        argResults!['seed'] == null ? null : int.parse(argResults!['seed']);
    final config = configs[0];
    final count = int.parse(argResults!['count']);

    final random = Random(seed);
    var engine = config.buildEngine<G>();

    for (var i = 0; i < count; ++i) {
      var game = startingGame;
      if (argResults!['refresh']) {
        engine.clearCache();
      }

      while (game.score != 1.0 && game.score != -1.0) {
        final move = await engine.chooseBest(game.getMoves(), game);
        final chance = move.perform(game);
        final outcome = chance.pick(random.nextDouble());
        game = outcome.outcome;
      }
    }

    print(engine.stats);
  }
}

class Compare<G extends Game<G>> extends ParseConfigCommand {
  final name = 'compare';
  final description = 'Compare the performance and/or decisions of two configs,'
      ' by playing a series of exactly the same games';

  final G startingGame;

  Compare(this.startingGame, ExpectiminimaxConfig defaultXmmConfig,
      MctsConfig defaultMctsConfig, List<List<String>> configSpecs)
      : super(defaultXmmConfig, defaultMctsConfig, configSpecs) {
    argParser.addOption('count',
        abbr: 'c', defaultsTo: '10', help: 'How many games to play');
    argParser.addOption('seed',
        abbr: 's', help: 'Random number generator seed.');
    argParser.addFlag('refresh',
        abbr: 'r',
        help: 'Whether or not to clear cache results between games',
        defaultsTo: false);
    argParser.addFlag('choices',
        help: 'Whether or not to check the choices match', defaultsTo: true);
  }

  @override
  void runWithConfigs(List<EngineConfig> configs) async {
    final seed =
        argResults!['seed'] == null ? null : int.parse(argResults!['seed']);
    final count = int.parse(argResults!['count']);
    final compareChoices = argResults!['choices'];

    final random = Random(seed);
    var algs = configs.map((c) => c.buildEngine<G>()).toList();

    for (var i = 0; i < count; ++i) {
      var game = startingGame;
      var turn = 0;
      if (argResults!['refresh'] && i != 0) {
        for (var c = 0; c < configs.length; ++c) {
          algs[c].clearCache();
        }
      }

      while (game.score != 1.0 && game.score != -1.0) {
        final moves = game.getMoves();
        final move = await algs[0].chooseBest(moves, game);
        for (var c = 1; c < configs.length; ++c) {
          final vsMove = await algs[c].chooseBest(moves, game);
          if (compareChoices && move != vsMove) {
            print('Difference on turn $turn, game $i');
            print('- Baseline chose ${move.description}');
            print('- Alternate config $c chose ${vsMove.description}');
            print('  (choosing baseline move and continuing)');
          }
        }
        final chance = move.perform(game);
        final outcome = chance.pick(random.nextDouble());
        game = outcome.outcome;
        ++turn;
      }
    }

    print('Baseline stats:');
    print(algs[0].stats);
    for (var c = 1; c < configs.length; ++c) {
      print('');
      print('Alternative stats #$c (--vs):');
      print(algs[c].stats);
    }
    for (var c = 1; c < configs.length; ++c) {
      print('');
      print('Comparative stats (alternative #$c - baseline):');
      print(algs[c].stats - algs[0].stats);
    }
  }
}

class Rank<G extends Game<G>> extends ParseConfigCommand {
  final name = 'rank';
  final description = 'Rank two configs in ELO, by playing a series of games'
      ' between them.';

  final G startingGame;

  Rank(this.startingGame, ExpectiminimaxConfig defaultXmmConfig,
      MctsConfig defaultMctsConfig, List<List<String>> configSpecs)
      : super(defaultXmmConfig, defaultMctsConfig, configSpecs) {
    argParser.addOption('count',
        abbr: 'c', defaultsTo: '10', help: 'Maximum number of games to play');
    argParser.addOption('seed',
        abbr: 's', help: 'Random number generator seed.');
    argParser.addOption('threads',
        defaultsTo: '8', help: 'Number of games to run concurrently.');
    argParser.addFlag('sprt',
        defaultsTo: false,
        help: 'Run SPRT (sequential probability ratio test), which tests until'
            ' --elo or --null-elo is proven for each engine, or max games is'
            ' hit.');
    argParser.addOption('alpha',
        defaultsTo: '0.05',
        help: 'alpha value for running SPRT, or, false positive rate');
    argParser.addOption('beta',
        defaultsTo: '0.05',
        help: 'beta value for running SPRT, or, false negative rate');
    argParser.addOption('elo',
        defaultsTo: '20',
        help: 'When running SPRT, this sets the alternative hypothesis ELO for'
            ' each engine.');
    argParser.addOption('null-elo',
        defaultsTo: '0',
        help: 'When running SPRT, this sets the null hypothesis ELO for each'
            ' engine.');
    argParser.addFlag('refresh',
        abbr: 'r',
        help: 'Whether or not to clear cache results between games',
        defaultsTo: false);
  }

  Thread startThread(List<EngineConfig> configs, Random random, bool refresh) {
    return Thread((events) {
      final algs = configs.map((c) => c.buildEngine<G>()).toList();
      events.on('game', (List<int> players) async {
        var game = startingGame;
        final aIdx = players[0];
        var bIdx = players[1];

        final playerA = algs[aIdx];
        final playerB = algs[bIdx];

        if (refresh) {
          algs[bIdx].clearCache();
          algs[aIdx].clearCache();
        }

        for (int i = 0; true; ++i) {
          if (game.score == 1.0 || game.score == -1.0) {
            events.emit('result', game.score);
            break;
          } else if (i == 1000) {
            events.emit('result', 0.0);
            break;
          }

          final moves = game.getMoves();
          if (moves.isEmpty) {
            events.emit('result', 0.0);
            break;
          }

          final Move<G> move;
          if (game.isMaxing) {
            move = await playerA.chooseBest(moves, game);
          } else {
            move = await playerB.chooseBest(moves, game);
          }
          final chance = move.perform(game);
          final outcome = chance.pick(random.nextDouble());
          game = outcome.outcome;
        }
      });
    });
  }

  void stopThreads(List<Thread> threads) {
    for (final thread in threads) {
      thread.events?.receivePort.close();
      thread.stop();
    }
  }

  @override
  void runWithConfigs(List<EngineConfig> configs) {
    final elo = FullHistoryElo<int>();
    elo.init(List.generate(configs.length, (i) => i));
    final seed =
        argResults!['seed'] == null ? null : int.parse(argResults!['seed']);
    final count = int.parse(argResults!['count']);
    final threadCount = int.parse(argResults!['threads']);

    final random = Random(seed);
    final refresh = argResults!['refresh'];

    print('[GAMES]');
    print('');
    print('[RATINGS]');
    print(elo);

    final esc = String.fromCharCode(27);
    final clearStr = '$esc[1A$esc[2K' * (configs.length + 2);

    final threads = List.generate(
        threadCount, (i) => startThread(configs, random, refresh));

    var startedGames = 0;
    var game = 0;
    for (final thread in threads) {
      var aIdx;
      var bIdx;
      runGame() {
        aIdx = random.nextInt(configs.length);
        bIdx = random.nextInt(configs.length - 1);
        if (bIdx >= aIdx) {
          ++bIdx;
        }
        startedGames++;
        thread.emit('game', <int>[aIdx, bIdx]);
      }

      thread.on('result', (double score) {
        game++;
        if (score == 1.0) {
          print('${clearStr}* game $game, $aIdx beats $bIdx');
          elo.victory(aIdx, bIdx);
        } else if (score == 0.0) {
          print('${clearStr}* game $game, $aIdx and $bIdx draw');
          elo.draw(aIdx, bIdx);
        } else if (score == -1.0) {
          print('${clearStr}* game $game, $bIdx beats $aIdx');
          elo.loss(aIdx, bIdx);
        }

        print('');
        print('[RATINGS]');
        print(elo);

        if (argResults!['sprt']) {
          final alpha = double.parse(argResults!['alpha']);
          final beta = double.parse(argResults!['beta']);
          final elo1 = double.parse(argResults!['null-elo']);
          final elo2 = double.parse(argResults!['elo']);
          final sprt =
              elo.sprt(alpha: alpha, beta: beta, elo1: elo1, elo2: elo2);
          if (sprt.length == configs.length) {
            stopThreads(threads);

            print('');
            print('Stopping on SPRT result!');
            print(sprt.entries
                .map((e) => '${e.key}:'
                    ' ${e.value ? "more likely $elo2" : "more likely $elo1"}')
                .join('\n'));
          }
        }

        if (startedGames < count) {
          runGame();
        } else {
          thread.events?.receivePort.close();
          thread.stop();
        }
      });

      runGame();
    }
  }
}

abstract class ParseConfigCommand extends Command {
  List<List<String>> configSpecs;
  final ExpectiminimaxConfig defaultXmmConfig;
  final MctsConfig defaultMctsConfig;

  ParseConfigCommand(
      this.defaultXmmConfig, this.defaultMctsConfig, this.configSpecs) {
    argParser.addCommand('xmm', xmmParser(defaultXmmConfig));
    argParser.addCommand('mcts', mctsParser(defaultMctsConfig));
    argParser.addCommand('served', servedEngineParser());
    argParser.addCommand('random', randomEngineParser());
    argParser.addCommand('nth', nthEngineParser());
  }

  void runWithConfigs(List<EngineConfig> configs);

  @override
  String get usageFooter => '''

Additionally, running this command requires specifying one or more engines:

    xmm               Expectiminimax game engine.
                      Example: $name xmm --max-depth 8
    mcts              Monte-Carlo Tree Search game engine.
                      Example: $name mcts --max-playouts 10000
    served            Engine runnnig with API launched via `serve` command.
                      Example: $name served localhost:8080
    random            Simple engine which just picks random moves.
                      Example: $name random --seed 0
    nth               Simple engine which always picks the nth move.
                      Example: $name nth -n 0

Some commands can accept multiple engines. These engines may be separated with '--vs' flags.

    --vs              Specify an additional engine to $name.
                      Example: $name xmm --max-depth 8 --vs mcts --max-playouts 1000 --vs random

'xmm' engine config options:

${xmmParser(defaultXmmConfig).usage.splitMapJoin(
            '\n',
            onNonMatch: (line) => '    $line',
          )}

'mcts' engine config options:

${mctsParser(defaultMctsConfig).usage.splitMapJoin(
            '\n',
            onNonMatch: (line) => '    $line',
          )}

'served' engine config options:

${servedEngineParser().usage.splitMapJoin(
            '\n',
            onNonMatch: (line) => '    $line',
          )}

'random' engine config options:

${randomEngineParser().usage.splitMapJoin(
            '\n',
            onNonMatch: (line) => '    $line',
          )}

'nth' engine config options:

${nthEngineParser().usage.splitMapJoin(
            '\n',
            onNonMatch: (line) => '    $line',
          )}
''';

  @override
  void run() {
    if (argResults?.command == null) {
      print('Error: no engine specified, cannot proceed.');
      print('');
      printUsage();
      return;
    }

    final configParser = ArgParser(allowTrailingOptions: false);
    configParser.addCommand('xmm', xmmParser(defaultXmmConfig));
    configParser.addCommand('mcts', mctsParser(defaultMctsConfig));
    configParser.addCommand('served', servedEngineParser());
    configParser.addCommand('random', randomEngineParser());
    configParser.addCommand('nth', nthEngineParser());

    try {
      final configs = [
        getPrimaryConfig(),
        ...configSpecs.map((args) {
          if (args.first.startsWith('-')) {
            throw 'Error: Specify an engine before engine flags: "$args"';
          }
          if (!{'xmm', 'mcts', 'served', 'random', 'nth'}
              .contains(args.first)) {
            throw 'Error: Invalid engine name: "${args.first}"';
          }
          try {
            return getConfigFromResults(configParser.parse(args));
          } catch (e) {
            throw 'Error: Misconfigured engine "$args"\n\n$e';
          }
        })
      ];

      runWithConfigs(configs);
    } on FormatException catch (e) {
      print(e);
      print('');
      printUsage();
    }
  }

  @override
  String get invocation =>
      '$name [--$name-flags] `engine` [--engine-flags] [--vs `engine [--engineflags] --vs ...]';

  ArgParser xmmParser(ExpectiminimaxConfig defaults) =>
      addXmmOptionsToParser(ArgParser(), defaults);

  ArgParser addXmmOptionsToParser(
          ArgParser parser, ExpectiminimaxConfig defaults) =>
      parser
        ..addOption('max-depth',
            abbr: 'd',
            defaultsTo: defaults.maxDepth.toString(),
            help: 'max depth to search')
        ..addOption('max-time',
            abbr: 't',
            defaultsTo: defaults.maxTime.inMilliseconds.toString(),
            help: 'max time to search, in milliseconds')
        ..addFlag('iterative-deepening',
            defaultsTo: defaults.iterativeDeepening,
            help: 'enable iterative deepening')
        ..addOption('chance-node-probe-window',
            allowed: [
              'none',
              'overlapping',
              'centerToEnd',
              'edgeToEnd',
            ],
            defaultsTo: defaults.chanceNodeProbeWindow.name,
            help: 'enable probing phase on chance nodes')
        ..addOption('transposition-table-size',
            defaultsTo: defaults.transpositionTableSize.toString(),
            help: 'size (in entry count) of transposition table')
        ..addFlag('strict-transpositions',
            defaultsTo: defaults.strictTranspositions,
            help: 'check == on transposition entries to avoid hash collisions')
        ..addOption('debug-setting', hide: true);

  ArgParser mctsParser(MctsConfig defaults) =>
      ArgParser(allowTrailingOptions: false)
        ..addOption('max-depth',
            abbr: 'd',
            defaultsTo: defaults.maxDepth.toString(),
            help: 'max depth to search')
        ..addOption('max-time',
            abbr: 't',
            defaultsTo: defaults.maxTime.inMilliseconds.toString(),
            help: 'max time to search, in milliseconds')
        ..addOption('max-playouts',
            abbr: 'p',
            defaultsTo: defaults.maxPlayouts.toString(),
            help: 'Max playouts before aborting search')
        ..addOption('expand-depth',
            abbr: 'e',
            defaultsTo: defaults.expandDepth.toString(),
            help: 'Max new deeper nodes to add to tree during expand phase')
        ..addOption('c-uct',
            defaultsTo: defaults.cUct.toString(),
            help: 'Constant parameter "c" for UCT selection')
        ..addOption('c-puct',
            defaultsTo: defaults.cPuct.toString(),
            help: 'Constant parameter "cpUCT" for pUCT selection');

  ArgParser randomEngineParser() => ArgParser(allowTrailingOptions: false)
    ..addOption('seed', abbr: 's', help: 'seed for random move selection.');

  ArgParser servedEngineParser() => ArgParser();

  ArgParser nthEngineParser() => ArgParser(allowTrailingOptions: false)
    ..addFlag('from-end',
        abbr: 'e', help: 'select nth move from the end instead of the start')
    ..addOption('n',
        abbr: 'n',
        defaultsTo: '0',
        help: '0-based index for which move to select');

  EngineConfig getPrimaryConfig() => getConfigFromResults(argResults!);

  EngineConfig getConfigFromResults(ArgResults results) {
    switch (results.command?.name) {
      case 'xmm':
        return getXmmConfig(results.command!);
      case 'mcts':
        return getMctsConfig(results.command!);
      case 'served':
        return getServedEngineConfig(results.command!);
      case 'random':
        return getRandomEngineConfig(results.command!);
      case 'nth':
        return getNthEngineConfig(results.command!);
      default:
        throw 'bad engine name ${results.command?.name}';
    }
  }

  ExpectiminimaxConfig getXmmConfig(ArgResults results) {
    return ExpectiminimaxConfig(
      maxDepth: int.parse(results['max-depth']),
      maxTime: Duration(milliseconds: int.parse(results['max-time'])),
      iterativeDeepening: results['iterative-deepening'],
      chanceNodeProbeWindow:
          ProbeWindow.values.byName(results['chance-node-probe-window']),
      transpositionTableSize: int.parse(results['transposition-table-size']),
      strictTranspositions: results['strict-transpositions'],
      // ignore: deprecated_member_use_from_same_package
      debugSetting: results['debug-setting'],
    );
  }

  MctsConfig getMctsConfig(ArgResults results) {
    return MctsConfig(
      maxDepth: int.parse(results['max-depth']),
      maxTime: Duration(milliseconds: int.parse(results['max-time'])),
      maxPlayouts: int.parse(results['max-playouts']),
      expandDepth: int.parse(results['expand-depth']),
      cUct: double.parse(results['c-uct']),
      cPuct: double.parse(results['c-puct']),
    );
  }

  ServedEngineConfig getServedEngineConfig(ArgResults results) {
    if (results.rest.length != 1) {
      throw FormatException('wrong number of arguments provided, expected'
          ' hostname, got ${results.rest}');
    }
    return ServedEngineConfig(server: results.rest.single);
  }

  RandomEngineConfig getRandomEngineConfig(ArgResults results) {
    return RandomEngineConfig(
      seed: results.wasParsed('seed') ? int.parse(results['seed']) : null,
    );
  }

  NthEngineConfig getNthEngineConfig(ArgResults results) {
    return NthEngineConfig(
      direction: results['from-end'] ? Direction.fromEnd : Direction.fromStart,
      offset: int.parse(results['n']),
    );
  }
}
