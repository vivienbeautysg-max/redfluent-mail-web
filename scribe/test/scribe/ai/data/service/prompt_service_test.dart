import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribe/scribe/ai/data/service/prompt_service.dart';
import 'package:scribe/scribe/ai/domain/model/ai_message.dart';

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw Exception('Not found');
  }

  @override
  void close({bool force = false}) {}
}

Dio _throwingDio() => Dio()..httpClientAdapter = _ThrowingAdapter();

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('PromptService', () {
    test('buildPromptByName should build prompt with input text', () async {
      // Arrange
      final service = PromptService(_throwingDio());

      // Act - this will use the real prompts.json file since the adapter throws
      final messages = await service.buildPromptByName('change-tone-casual', 'Hello, how are you?');

      // Assert
      expect(messages.length, 2);
      expect(messages.first.role, AIRole.system);
      expect(messages.last.role, AIRole.user);
      expect(messages.last.content, contains('Hello, how are you?'));
    });

    test('buildPromptByName should build prompt with input text and task', () async {
      // Arrange
      final service = PromptService(_throwingDio());
      
      // Act - this will use the real prompts.json file since the test client throws
      final messages = await service.buildPromptByName('custom-prompt-mail', 'Hello, how are you?', task: 'Make it more casual');

      // Assert
      expect(messages.length, 2);
      expect(messages.first.role, AIRole.system);
      expect(messages.last.role, AIRole.user);
      expect(messages.last.content, contains('Hello, how are you?'));
      expect(messages.last.content, contains('Make it more casual'));
    });
  });

  group('PromptService getPromptByName', () {
    test('getPromptByName should return correct prompt from assets', () async {
      final service = PromptService(_throwingDio());

      final prompt = await service.getPromptByName('change-tone-casual');

      expect(prompt.name, 'change-tone-casual');
      expect(prompt.messages.length, greaterThan(0));
    });

    test('getPromptByName should throw exception for non-existent prompt',
        () async {
      final service = PromptService(_throwingDio());

      await expectLater(
        service.getPromptByName('non-existent-prompt'),
        throwsException,
      );
    });
  });
}