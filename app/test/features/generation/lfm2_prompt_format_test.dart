import 'package:bayaz_ai/features/generation/lfm2_prompt_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final formatter = Lfm2PromptFormat();

  test('formats a single prompt with the LFM2 start token', () {
    expect(
      formatter.formatPrompt('Explain gravity.'),
      '<|startoftext|><|im_start|>user\n'
      'Explain gravity.<|im_end|>\n'
      '<|im_start|>assistant\n',
    );
  });

  test('formats system and user messages in the published order', () {
    expect(
      formatter.formatMessages(const [
        {'role': 'system', 'content': 'Use simple language.'},
        {'role': 'user', 'content': 'Explain gravity.'},
      ]),
      '<|startoftext|><|im_start|>system\n'
      'Use simple language.<|im_end|>\n'
      '<|im_start|>user\n'
      'Explain gravity.<|im_end|>\n'
      '<|im_start|>assistant\n',
    );
  });

  test('does not add a second assistant prefix after an assistant message', () {
    expect(
      formatter.formatMessages(const [
        {'role': 'user', 'content': 'Question'},
        {'role': 'assistant', 'content': 'Answer'},
      ]),
      '<|startoftext|><|im_start|>user\n'
      'Question<|im_end|>\n'
      '<|im_start|>assistant\n'
      'Answer<|im_end|>\n',
    );
  });
}
