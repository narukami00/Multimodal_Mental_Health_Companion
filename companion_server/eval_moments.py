"""Measures how well the language model finds good moments, so a model swap or a prompt change is judged on numbers.

Each case is a message (and sometimes the lines before it) with the right answer: a moment that must contain certain words, or
NONE. It runs the real `LlmService.extract_moment_async` (the model plus the safety checks) and reports, by kind of case, how
often the answer was right. Wrong answers of the dangerous kind (a moment made out of a negative, sensitive or empty message)
are counted separately, because those cost trust; a missed moment costs little.

Run (from companion_server):  python eval_moments.py            # whatever backend is configured
                              SOLACE_LLM_BACKEND=ct2 python eval_moments.py     # the built-in small model
                              SOLACE_LLM_BACKEND=llamacpp python eval_moments.py  # the llama.cpp server (SOLACE_LLAMACPP_URL)
"""
import asyncio
import json
import sys
import time
from typing import Dict, List, Optional

from llm_service import LlmService

Context = List[Dict[str, str]]


def case(kind: str, text: str, expect: Optional[List[str]], context: Optional[Context] = None) -> Dict:
    """[expect] is the words (all must appear, lower case) the kept moment must contain, or None when the answer must be NONE."""
    return {"kind": kind, "text": text, "expect": expect, "context": context or []}


CASES = [
    # A clear good thing, said plainly: it should be kept, in their words.
    case("clear", "I went for a long walk by the river this morning and it was lovely.", ["walk", "river"]),
    case("clear", "Had coffee with my sister today. We laughed so much I forgot about everything else.", ["sister", "laughed"]),
    case("clear", "I finally finished the painting I started in March and I'm really proud of it.", ["painting", "proud"]),
    case("clear", "My neighbour brought me soup when I was tired and it made my whole day.", ["soup"]),
    case("clear", "We cooked together last night and it was the most fun I've had in weeks.", ["cooked", "fun"]),
    case("clear", "I managed to get out of bed early and made pancakes, which felt really good.", ["pancakes"]),
    case("clear", "Today my dog learned to roll over and I couldn't stop smiling.", ["dog", "smiling"]),
    case("clear", "I called my old friend Sam after months and we talked for two hours. I'm so glad I did.", ["sam", "glad"]),
    case("clear", "Sat on the balcony with tea and watched the rain. It was so calm and nice.", ["balcony", "tea"]),
    case("clear", "I passed my driving test today! I'm so happy.", ["driving test", "happy"]),
    # Good thing buried in a longer, mixed message.
    case("buried", "Work has been exhausting and I'm behind on everything. But on Thursday I went swimming and it was great. Then I got home and the inbox was full again.", ["swimming"]),
    case("buried", "Tired today. Slept badly. The only nice part was lunch with Priya, we sat in the park and it was really lovely.", ["priya", "park"]),
    case("buried", "Not the best week, honestly. My mum sent me a voice note singing happy birthday and it made me tear up in a good way.", ["mum", "birthday"]),
    case("buried", "Everything feels heavy lately. I did bake bread on Sunday though, and the smell filled the flat, which I loved.", ["bread"]),
    # A warm comment that only makes sense with the lines before it.
    case("referent", "That was a great idea.", ["walk"], [
        {"role": "assistant", "text": "Would you like to take a short walk after lunch?"},
        {"role": "user", "text": "Maybe, I haven't been outside much."},
    ]),
    case("referent", "I loved that.", ["cooking"], [
        {"role": "user", "text": "I tried cooking something new with my flatmate yesterday."},
        {"role": "assistant", "text": "That sounds like a nice way to spend an evening. How was the cooking?"},
    ]),
    case("referent", "Yeah that really helped.", ["breathing"], [
        {"role": "assistant", "text": "Try three slow breaths, in through the nose and out slowly."},
        {"role": "user", "text": "ok doing the breathing now"},
    ]),
    # No good moment: must be NONE.
    case("none", "I don't know what to do about work. Everything feels like too much.", None),
    case("none", "What time is it in Tokyo right now?", None),
    case("none", "I'm just tired. Not much to say today.", None),
    case("none", "My manager shouted at me again and I hated every minute of the meeting.", None),
    case("none", "I guess it was fine. Nothing special happened.", None),
    case("none", "Can you recommend something to help me sleep?", None),
    case("none", "Yeah.", None),
    case("none", "Thanks, that's helpful.", None),
    # Negated or sarcastic: the warm word is there, the good thing is not.
    case("negated", "I didn't enjoy the party at all, I just wanted to go home.", None),
    case("negated", "Great, another meeting that could have been an email. Really wonderful.", None),
    case("negated", "I wasn't happy with how the day went, nothing felt good.", None),
    case("negated", "It was not a nice evening. I never want to go back there.", None),
    # Good but a topic Sol never offers to keep on its own.
    case("sensitive", "After the funeral my sister and I sat together and laughed about grandad. It felt good.", None),
    case("sensitive", "The doctor said the diagnosis is manageable and I felt so relieved walking home.", None),
    case("sensitive", "I paid off a bit of my debt today and I'm really proud of myself.", None),
    case("sensitive", "I stayed in the hospital garden for an hour and the sun was lovely.", None),
    # Praise with nothing in it: keeping it would be a fragment nobody can read back.
    case("vague", "That was so good, I loved it.", None),
    case("vague", "It was great!", None),
    case("vague", "Nice, I'm happy with that.", None),
]

DANGEROUS = {"none", "negated", "sensitive", "vague"}


async def main() -> int:
    llm = LlmService()
    if not llm.initialize():
        print("The language model could not be loaded.")
        return 1
    print(f"backend: {llm.backend}   cases: {len(CASES)}\n")
    by_kind: Dict[str, List[bool]] = {}
    unsafe: List[str] = []
    failures: List[str] = []
    seconds = 0.0
    for c in CASES:
        t0 = time.time()
        got = await llm.extract_moment_async(c["text"], c["context"])
        seconds += time.time() - t0
        if c["expect"] is None:
            ok = got is None
            if not ok:
                unsafe.append(f'[{c["kind"]}] {c["text"]!r} -> {got!r}')
        else:
            ok = got is not None and all(w in got.lower() for w in c["expect"])
            if not ok:
                failures.append(f'[{c["kind"]}] {c["text"]!r} -> {got!r}   (wanted {c["expect"]})')
        by_kind.setdefault(c["kind"], []).append(ok)
    print("right answers by kind:")
    for kind, results in by_kind.items():
        print(f"  {kind:10s} {sum(results):2d}/{len(results):2d}")
    wanted = [r for k, rs in by_kind.items() if k not in DANGEROUS for r in rs]
    safe = [r for k, rs in by_kind.items() if k in DANGEROUS for r in rs]
    print(f"\nfinds the moment when there is one: {sum(wanted)}/{len(wanted)}")
    print(f"keeps nothing when there should be nothing: {sum(safe)}/{len(safe)}   (anything less is a wrong moment)")
    print(f"average time per message: {seconds / len(CASES):.2f} s")
    if unsafe:
        print("\nWRONG MOMENTS (should have been nothing):")
        print("\n".join("  " + u for u in unsafe))
    if failures:
        print("\nMISSED OR WRONG:")
        print("\n".join("  " + f for f in failures))
    print("\n" + json.dumps({"backend": llm.backend, "found": f"{sum(wanted)}/{len(wanted)}", "quiet": f"{sum(safe)}/{len(safe)}"}))
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
