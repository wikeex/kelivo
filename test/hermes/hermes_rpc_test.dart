import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/hermes/hermes_config.dart';
import 'package:Kelivo/hermes/hermes_event_bus.dart';
import 'package:Kelivo/hermes/hermes_gateway.dart';
import 'package:Kelivo/hermes/hermes_rpc.dart';

/// A mock HermesGateway that records RPC calls.
class MockGateway extends HermesGateway {
  MockGateway() : super(eventBus: HermesEventBus(), config: _mockConfig());

  final recordedRpcs = <String>[];

  @override
  Future<dynamic> sendRpc(String method, [Map<String, dynamic>? params]) async {
    recordedRpcs.add(method);
    switch (method) {
      case 'session.create':
        return {'session_id': 'sess-001'};
      case 'session.resume':
        return {'session_id': params?['session_id'] ?? ''};
      case 'session.most_recent':
        return {'session_id': 'sess-recent'};
      case 'session.list':
        return [
          {'session_id': 'sess-1', 'created_at': '2026-01-01T00:00:00Z'},
        ];
      case 'session.search':
        return [
          {
            'session_id': 'sess-2',
            'title': 'found',
            'created_at': '2026-01-02T00:00:00Z',
          },
        ];
      case 'prompt.submit':
        return null;
      case 'session.interrupt':
        return null;
      case 'session.close':
        return null;
      case 'session.delete':
        return null;
      case 'session.title':
        return null;
      case 'session.usage':
        return {
          'input_tokens': 100,
          'output_tokens': 50,
          'total_tokens': 150,
          'cost_usd': 0.002,
          'turn_count': 3,
        };
      default:
        return null;
    }
  }

  @override
  Future<void> connect(HermesBackendBox backend) async {}
}

HermesConfig _mockConfig() => HermesConfig();

void main() {
  late MockGateway gateway;

  setUp(() {
    gateway = MockGateway();
  });

  group('HermesSessionRpc', () {
    test('sessionCreate returns session ID', () async {
      final id = await gateway.sessionCreate();
      expect(id, 'sess-001');
      expect(gateway.recordedRpcs, contains('session.create'));
    });

    test('sessionResume returns session ID', () async {
      final id = await gateway.sessionResume('sess-001');
      expect(id, 'sess-001');
      expect(gateway.recordedRpcs, contains('session.resume'));
    });

    test('sessionMostRecent returns session ID', () async {
      final id = await gateway.sessionMostRecent();
      expect(id, 'sess-recent');
      expect(gateway.recordedRpcs, contains('session.most_recent'));
    });

    test('sessionList returns summaries', () async {
      final list = await gateway.sessionList();
      expect(list.length, 1);
      expect(list[0].sessionId, 'sess-1');
    });

    test('sessionSearch returns matching summaries', () async {
      final results = await gateway.sessionSearch('found');
      expect(results.length, 1);
      expect(results[0].title, 'found');
    });

    test('sessionInterrupt does not throw', () async {
      await gateway.sessionInterrupt('sess-001');
      expect(gateway.recordedRpcs, contains('session.interrupt'));
    });

    test('sessionClose does not throw', () async {
      await gateway.sessionClose('sess-001');
      expect(gateway.recordedRpcs, contains('session.close'));
    });

    test('sessionTitle does not throw', () async {
      await gateway.sessionTitle('sess-001', 'New Title');
      expect(gateway.recordedRpcs, contains('session.title'));
    });

    test('sessionUsage returns usage data', () async {
      final usage = await gateway.sessionUsage('sess-001');
      expect(usage['total_tokens'], 150);
    });
  });

  group('HermesPromptRpc', () {
    test('promptSubmit records method', () async {
      await gateway.promptSubmit(sessionId: 'sess-001', prompt: 'Hello');
      expect(gateway.recordedRpcs, contains('prompt.submit'));
    });
  });

  group('HermesBillingRpc', () {
    test('billingCredits returns 0.0 from mock', () async {
      final credits = await gateway.billingCredits();
      // Mock returns null, so defaults to 0.0
      expect(credits, 0.0);
    });
  });

  group('HermesSessionSummary', () {
    test('fromJson parses correctly', () {
      final json = {
        'session_id': 'sess-1',
        'title': 'Test Session',
        'created_at': '2026-06-01T12:00:00Z',
        'last_active_at': '2026-06-01T14:00:00Z',
        'message_count': 5,
      };
      final summary = HermesSessionSummary.fromJson(json);
      expect(summary.sessionId, 'sess-1');
      expect(summary.title, 'Test Session');
      expect(summary.messageCount, 5);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'session_id': 'sess-2',
        'created_at': '2026-06-01T12:00:00Z',
      };
      final summary = HermesSessionSummary.fromJson(json);
      expect(summary.sessionId, 'sess-2');
      expect(summary.title, isNull);
      expect(summary.messageCount, 0);
    });

    test('fromJson handles null dates', () {
      final json = {'session_id': 'sess-3', 'created_at': null};
      final summary = HermesSessionSummary.fromJson(json);
      // Should default to DateTime.now() — just verify no crash
      expect(summary.sessionId, 'sess-3');
    });
  });
}
