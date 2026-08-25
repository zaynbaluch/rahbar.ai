import 'package:llama_cpp_dart/llama_cpp_dart.dart';

/// Prompt formatting published for Liquid AI's LFM2 chat checkpoints.
class Lfm2PromptFormat extends PromptFormat {
  Lfm2PromptFormat()
      : super(
          PromptFormatType.chatml,
          inputSequence: '<|im_start|>user\n',
          outputSequence: '<|im_start|>assistant\n',
          systemSequence: '<|im_start|>system\n',
          stopSequence: '<|im_end|>\n',
        );

  static const String _startOfText = '<|startoftext|>';

  @override
  String formatPrompt(String prompt) =>
      '$_startOfText$inputSequence$prompt$stopSequence$outputSequence';

  @override
  String formatMessages(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer(_startOfText);
    for (final message in messages) {
      final content = message['content']?.toString() ?? '';
      switch (message['role']) {
        case 'system':
          buffer.write('$systemSequence$content$stopSequence');
        case 'user':
          buffer.write('$inputSequence$content$stopSequence');
        case 'assistant':
          buffer.write('$outputSequence$content$stopSequence');
      }
    }
    if (messages.isEmpty || messages.last['role'] != 'assistant') {
      buffer.write(outputSequence);
    }
    return buffer.toString();
  }
}
