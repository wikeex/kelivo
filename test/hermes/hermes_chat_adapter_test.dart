import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/hermes/hermes_chat_adapter.dart';
import 'package:Kelivo/hermes/hermes_event_bus.dart';
import 'package:Kelivo/hermes/hermes_models.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';

void main() {
  group('HermesChatAdapter', () {
    test('emits ChatStreamChunk on MessageDelta event', () async {
      final bus = HermesEventBus();
      final adapter = HermesChatAdapter(eventBus: bus, sessionId: 's1');
      final chunks = <ChatStreamChunk>[];

      adapter.chunkStream.listen(chunks.add);

      bus.emit(MessageDelta(sessionId: 's1', text: 'Hello'));
      await Future.delayed(Duration.zero);

      expect(chunks.length, 1);
      expect(chunks[0].content, 'Hello');

      adapter.dispose();
    });

    test('accumulates text across multiple MessageDelta events', () async {
      final bus = HermesEventBus();
      final adapter = HermesChatAdapter(eventBus: bus, sessionId: 's1');
      final chunks = <ChatStreamChunk>[];

      adapter.chunkStream.listen(chunks.add);

      bus.emit(MessageDelta(sessionId: 's1', text: 'Hello '));
      bus.emit(MessageDelta(sessionId: 's1', text: 'world!'));
      await Future.delayed(Duration.zero);

      expect(chunks.length, 2);
      expect(chunks.last.content, 'Hello world!');

      adapter.dispose();
    });

    test('parses MessageComplete and sets isDone', () async {
      final bus = HermesEventBus();
      final adapter = HermesChatAdapter(eventBus: bus, sessionId: 's1');
      final chunks = <ChatStreamChunk>[];

      adapter.chunkStream.listen(chunks.add);

      bus.emit(MessageDelta(sessionId: 's1', text: 'response'));
      bus.emit(MessageComplete(sessionId: 's1'));
      await Future.delayed(Duration.zero);

      expect(chunks.length, 2);
      expect(chunks[0].isDone, false);
      expect(chunks[1].isDone, true);

      adapter.dispose();
    });

    test('captures reasoning delta', () async {
      final bus = HermesEventBus();
      final adapter = HermesChatAdapter(eventBus: bus, sessionId: 's1');
      final chunks = <ChatStreamChunk>[];

      adapter.chunkStream.listen(chunks.add);

      bus.emit(ReasoningDelta(sessionId: 's1', text: 'thinking...'));
      await Future.delayed(Duration.zero);

      expect(chunks.length, 1);
      expect(chunks[0].reasoning, 'thinking...');

      adapter.dispose();
    });

    test('treats ThinkingDelta as reasoning', () async {
      final bus = HermesEventBus();
      final adapter = HermesChatAdapter(eventBus: bus, sessionId: 's1');
      final chunks = <ChatStreamChunk>[];

      adapter.chunkStream.listen(chunks.add);

      bus.emit(ThinkingDelta(sessionId: 's1', text: 'thinking block'));
      await Future.delayed(Duration.zero);

      expect(chunks.length, 1);
      expect(chunks[0].reasoning, 'thinking block');

      adapter.dispose();
    });

    test('captures tool start and complete events', () async {
      final bus = HermesEventBus();
      final adapter = HermesChatAdapter(eventBus: bus, sessionId: 's1');
      final chunks = <ChatStreamChunk>[];

      adapter.chunkStream.listen(chunks.add);

      bus.emit(
        ToolStart(sessionId: 's1', name: 'bash', args: {'cmd': 'ls'}, index: 0),
      );
      bus.emit(
        ToolComplete(
          sessionId: 's1',
          name: 'bash',
          duration: 1.5,
          ok: true,
          index: 0,
        ),
      );
      await Future.delayed(Duration.zero);

      expect(chunks.length, 2);
      expect(chunks[0].toolCalls, isNotNull);
      expect(chunks[0].toolCalls!.length, 1);
      expect(chunks[0].toolCalls![0].name, 'bash');
      expect(chunks[1].toolResults, isNotNull);
      expect(chunks[1].toolResults!.length, 1);

      adapter.dispose();
    });

    test('ignores events for other sessions', () async {
      final bus = HermesEventBus();
      final adapter = HermesChatAdapter(eventBus: bus, sessionId: 's1');
      final chunks = <ChatStreamChunk>[];

      adapter.chunkStream.listen(chunks.add);

      bus.emit(MessageDelta(sessionId: 's2', text: 'Should be ignored'));
      await Future.delayed(Duration.zero);

      expect(chunks, isEmpty);

      adapter.dispose();
    });

    test('completes completionFuture on MessageComplete', () async {
      final bus = HermesEventBus();
      final adapter = HermesChatAdapter(eventBus: bus, sessionId: 's1');
      final done = <void>[];

      adapter.completionFuture.then((_) => done.add(null));

      bus.emit(MessageComplete(sessionId: 's1'));
      await Future.delayed(Duration.zero);

      expect(done.length, 1);

      adapter.dispose();
    });

    test('completes completionFuture with error on HermesError', () async {
      final bus = HermesEventBus();
      final adapter = HermesChatAdapter(eventBus: bus, sessionId: 's1');
      final errors = <Object>[];

      adapter.completionFuture.catchError((e) => errors.add(e));

      bus.emit(HermesError(sessionId: 's1', message: 'Something went wrong'));
      await Future.delayed(Duration.zero);

      expect(errors.length, 1);

      adapter.dispose();
    });

    test('does not emit after isDone', () async {
      final bus = HermesEventBus();
      final adapter = HermesChatAdapter(eventBus: bus, sessionId: 's1');
      final chunks = <ChatStreamChunk>[];

      adapter.chunkStream.listen(chunks.add);

      bus.emit(MessageComplete(sessionId: 's1'));
      bus.emit(MessageDelta(sessionId: 's1', text: 'Should be ignored'));
      await Future.delayed(Duration.zero);

      expect(chunks.length, 1);
      expect(chunks[0].isDone, true);

      adapter.dispose();
    });

    test('completionFuture set to null on dispose', () async {
      final bus = HermesEventBus();
      final adapter = HermesChatAdapter(eventBus: bus, sessionId: 's1');
      adapter.dispose();

      // Should not throw
      bus.emit(MessageDelta(sessionId: 's1', text: 'after dispose'));
      await Future.delayed(Duration.zero);
    });
  });
}
