import '../../core/models/user_profile.dart';

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.prompt,
    required this.options,
  });

  final String id;
  final String prompt;
  final List<String> options;
}

const erqSQuestions = [
  QuizQuestion(
    id: 'erq_s_1',
    prompt:
        'I control my emotions by changing the way I think about the situation I am in.',
    options: _agreementOptions,
  ),
  QuizQuestion(
    id: 'erq_s_2',
    prompt:
        'When I want to feel more positive emotion, I change what I am thinking about.',
    options: _agreementOptions,
  ),
  QuizQuestion(
    id: 'erq_s_3',
    prompt:
        'When I want to feel less negative emotion, I change what I am thinking about.',
    options: _agreementOptions,
  ),
  QuizQuestion(
    id: 'erq_s_4',
    prompt: 'I control my emotions by not expressing them.',
    options: _agreementOptions,
  ),
  QuizQuestion(
    id: 'erq_s_5',
    prompt: 'I keep my emotions to myself.',
    options: _agreementOptions,
  ),
  QuizQuestion(
    id: 'erq_s_6',
    prompt:
        'When I am feeling negative emotions, I make sure not to express them.',
    options: _agreementOptions,
  ),
];

const gad7Questions = [
  QuizQuestion(
    id: 'gad7_1',
    prompt: 'Feeling nervous, anxious, or on edge',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'gad7_2',
    prompt: 'Not being able to stop or control worrying',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'gad7_3',
    prompt: 'Worrying too much about different things',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'gad7_4',
    prompt: 'Trouble relaxing',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'gad7_5',
    prompt: 'Being so restless that it is hard to sit still',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'gad7_6',
    prompt: 'Becoming easily annoyed or irritable',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'gad7_7',
    prompt: 'Feeling afraid as if something awful might happen',
    options: _frequencyOptions,
  ),
];

const phq9Questions = [
  QuizQuestion(
    id: 'phq9_1',
    prompt: 'Little interest or pleasure in doing things',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'phq9_2',
    prompt: 'Feeling down, depressed, or hopeless',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'phq9_3',
    prompt: 'Trouble falling or staying asleep, or sleeping too much',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'phq9_4',
    prompt: 'Feeling tired or having little energy',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'phq9_5',
    prompt: 'Poor appetite or overeating',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'phq9_6',
    prompt:
        'Feeling bad about yourself — or that you are a failure or have let yourself or your family down',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'phq9_7',
    prompt:
        'Trouble concentrating on things, such as reading the newspaper or watching television',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'phq9_8',
    prompt:
        'Moving or speaking so slowly that other people could have noticed? Or the opposite — being so fidgety or restless that you have been moving around a lot more than usual',
    options: _frequencyOptions,
  ),
  QuizQuestion(
    id: 'phq9_9',
    prompt:
        'Thoughts that you would be better off dead or of hurting yourself in some way',
    options: _frequencyOptions,
  ),
];

const _agreementOptions = [
  'Strongly disagree',
  'Disagree',
  'Somewhat disagree',
  'Neither',
  'Somewhat agree',
  'Agree',
  'Strongly agree',
];

const _frequencyOptions = [
  'Not at all',
  'Several days',
  'More than half the days',
  'Nearly every day',
];

List<QuizQuestion> questionsFor(QuizBlock block) {
  return switch (block) {
    QuizBlock.erqS => erqSQuestions,
    QuizBlock.gad7 => gad7Questions,
    QuizBlock.phq9 => phq9Questions,
  };
}

Map<String, int> answersFor(UserProfile profile, QuizBlock block) {
  return switch (block) {
    QuizBlock.erqS => profile.erqSAnswers,
    QuizBlock.gad7 => profile.gad7Answers,
    QuizBlock.phq9 => profile.phq9Answers,
  };
}

int? scoreFor(UserProfile profile, QuizBlock block) {
  final questions = questionsFor(block);
  final answers = answersFor(profile, block);
  if (questions.any((question) => !answers.containsKey(question.id))) {
    return null;
  }
  var score = 0;
  for (final question in questions) {
    score += answers[question.id]!;
  }
  return score;
}
