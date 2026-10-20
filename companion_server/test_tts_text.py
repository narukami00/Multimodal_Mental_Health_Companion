"""Speech text normalisation: numbers, taka and lakh, times, short forms, names, and clause splitting. Pure functions, no model."""
import pytest

from tts_text import normalize_for_speech, number_to_words, split_clauses


@pytest.mark.parametrize("n, words", [
    (0, "zero"), (7, "seven"), (13, "thirteen"), (40, "forty"), (99, "ninety nine"), (100, "one hundred"),
    (204, "two hundred four"), (5000, "five thousand"), (12345, "twelve thousand three hundred forty five"),
    (1_000_000, "one million"),
])
def test_numbers_are_spelled_the_way_they_are_said(n, words):
    assert number_to_words(n) == words


@pytest.mark.parametrize("n, words", [
    (100_000, "one lakh"), (250_000, "two lakh fifty thousand"), (12_000_000, "one crore twenty lakh"), (10_200_000, "one crore two lakh"), (30_000_000, "three crore"),
])
def test_lakh_and_crore(n, words):
    assert number_to_words(n, south_asian=True) == words


@pytest.mark.parametrize("text, spoken", [
    ("Tk 250", "two hundred fifty taka"),
    ("It cost Tk 5,000 today.", "It cost five thousand taka today."),
    ("৳500", "five hundred taka"),
    ("BDT 1,200", "one thousand two hundred taka"),
    ("250 taka", "two hundred fifty taka"),
    ("about 1 lakh", "about one lakh"),
    ("2.5 lakh taka", "two point five lakh taka"),
    ("Tk 1,00,000", "one lakh taka"),
    ("rent is Tk 12,00,000", "rent is twelve lakh taka"),
    ("$20", "twenty dollars"),
    ("Tk 5 lakh", "five lakh taka"),
])
def test_money_in_taka_and_other_currencies(text, spoken):
    assert normalize_for_speech(text) == spoken


@pytest.mark.parametrize("text, spoken", [
    ("You walked 5,000 steps.", "You walked five thousand steps."),
    ("About 3.5 hours", "About three point five hours"),
    ("50% of the week", "fifty percent of the week"),
    ("at 5:30 pm", "at five thirty PM"),
    ("at 9:05", "at nine oh five"),
    ("at 7:00", "at seven o'clock"),
    ("the 1st and the 22nd", "the first and the twenty second"),
    ("back in 2025", "back in twenty twenty five"),
    ("since 1999", "since nineteen ninety nine"),
])
def test_numbers_times_percentages_ordinals_and_years(text, spoken):
    assert normalize_for_speech(text) == spoken


def test_short_forms_and_markup_are_dealt_with():
    assert normalize_for_speech("Dr. Rahman said so") == "Doctor Rahman said so"
    assert normalize_for_speech("**Great** job 😊 today") == "Great job today"
    assert normalize_for_speech("cats vs. dogs") == "cats versus dogs"


def test_names_can_be_respelled_without_code():
    assert normalize_for_speech("Hi Rafsan", {"Rafsan": "Raf-sahn"}) == "Hi Raf-sahn"
    assert normalize_for_speech("Rafsanjani is different", {"Rafsan": "Raf-sahn"}) == "Rafsanjani is different"  # whole words only


def test_plain_sentences_are_left_alone():
    sentence = "That sounds like a really lovely morning, and I'm so glad."
    assert normalize_for_speech(sentence) == sentence


def test_clauses_are_split_at_punctuation_with_their_closing_mark():
    assert split_clauses("It's okay, really. Take your time!") == [("It's okay,", ","), ("really.", "."), ("Take your time!", "!")]
    assert split_clauses("What was the best part? Even if small.") == [("What was the best part?", "?"), ("Even if small.", ".")]


def test_a_tiny_piece_joins_the_next_clause_and_empty_text_gives_nothing():
    assert split_clauses("Oh, that sounds really lovely.") == [("Oh, that sounds really lovely.", ".")]
    assert split_clauses("   ") == []
