import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/providers/hermes_chat_provider.dart';
import 'package:Kelivo/hermes/hermes_config.dart';
import 'package:Kelivo/hermes/hermes_event_bus.dart';
import 'package:Kelivo/hermes/hermes_gateway.dart';
import 'package:Kelivo/hermes/hermes_rpc.dart';

/// Mock gateway returning real Hermes server response shapes.
class ServerFormatMockGateway extends HermesGateway {
  ServerFormatMockGateway() : super(eventBus: HermesEventBus(), config: _cfg());

  @override
  Future<dynamic> sendRpc(String method, [Map<String, dynamic>? params]) async {
    switch (method) {
      case 'session.list':
        return {
          'sessions': [
            {
              'id': 'sess-real-1',
              'title': 'My chat',
              'preview': 'hello',
              'started_at': 1717200000,
              'message_count': 3,
              'source': 'tui',
            },
          ],
        };
      case 'session.history':
        return {
          'count': 2,
          'messages': [
            {'role': 'user', 'text': 'Hello'},
            {'role': 'assistant', 'text': 'Hi there', 'reasoning': 'thinking'},
          ],
        };
      case 'session.resume':
        return {
          'session_id': 'live-real-1',
          'resumed': params?['session_id'],
          'messages': [
            {'role': 'user', 'text': 'Hello'},
            {'role': 'assistant', 'text': 'Hi there', 'reasoning': 'thinking'},
          ],
        };
    }
  }

  @override
  Future<void> connect(HermesBackendBox backend) async {}
}

HermesConfig _cfg() {
  final c = HermesConfig();
  return c;
}

void main() {
  late ServerFormatMockGateway gateway;

  setUp(() {
    gateway = ServerFormatMockGateway();
  });

  test('sessionList parses wrapped sessions array from real server', () async {
    final list = await gateway.sessionList();
    expect(list.length, 1, reason: 'should unwrap {sessions: [...]}');
    expect(list[0].sessionId, 'sess-real-1');
    expect(list[0].title, 'My chat');
    expect(list[0].messageCount, 3);
  });

  test('sessionResumeDetailed uses live id and embeds messages', () async {
    final resume = await gateway.sessionResumeDetailed('sess-real-1');
    expect(resume.liveSessionId, 'live-real-1');
    expect(resume.storedSessionId, 'sess-real-1');
    expect(resume.messages.length, 2);
  });

  test('sessionHistory parses wrapped messages array from real server', () async {
    final history = await gateway.sessionHistory('live-real-1');
    expect(history.length, 2, reason: 'should unwrap {messages: [...]}');
    expect(history[0]['text'], 'Hello');
    expect(history[1]['text'], 'Hi there');

    final userMsg = HermesChatMessage.fromHermes(history[0]);
    final assistantMsg = HermesChatMessage.fromHermes(history[1]);
    expect(userMsg.content, 'Hello');
    expect(assistantMsg.content, 'Hi there');
    expect(assistantMsg.reasoning, 'thinking');
  });

  test('HermesSessionSummary accepts server id/started_at fields', () {
    final summary = HermesSessionSummary.fromJson({
      'id': 'sess-real-1',
      'title': 'My chat',
      'started_at': 1717200000,
      'message_count': 3,
    });
    expect(summary.sessionId, 'sess-real-1');
    expect(summary.title, 'My chat');
    expect(summary.messageCount, 3);
    expect(summary.createdAt.year, 2024);
  });
}
