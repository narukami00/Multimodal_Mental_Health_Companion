"""Adds the activity candidates you approved to the live library.

Review `mobile_application/tool/activity_candidates_review.md`: tick the rows you approve (`- [x]`) and edit any wording in place. Then run

    python mobile_application/tool/merge_activity_candidates.py          # shows what it would do
    python mobile_application/tool/merge_activity_candidates.py --write  # does it

Only ticked rows are merged. The title, description, minutes, effort, "when" and "suits" are read from YOUR sheet, so your edits
win. Each merged entry becomes an approved lifestyle entry reviewed by the project owner, and is removed from the candidates file.
Nothing unticked is touched. The result is validated the way the app validates it (unique ids and titles, known tags, sane times).
"""
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / 'mobile_application' / 'tool' / 'activity_candidates_review.md'
CANDIDATES = ROOT / 'mobile_application' / 'tool' / 'activity_candidates.json'
LIVE = ROOT / 'mobile_application' / 'assets' / 'activity_library.json'

ROW = re.compile(r'^\| - \[([ xX])\] \| ([a-z]+-\d+) \| \*\*(.+?)\*\*\. (.*?) \| (\d+) \| (low|medium|high) \| (.*?) \| (.*?) \|\s*$')
STATES = {'steady', 'quiet', 'bright', 'wobbly', 'tender'}
CONTEXTS = {'home', 'alone', 'short_break', 'outdoors', 'with_someone', 'low_energy', 'work', 'relationships', 'sleep', 'health', 'money'}
BLOCKED = ['self-harm', 'self harm', 'suicide', 'kill yourself', 'overdose', 'cutting yourself', 'alcohol', 'cocaine', 'heroin', 'cannabis',
           'drug', 'diagnose', 'cure', 'treat depression', 'stop taking medication', 'replace therapy', 'push through pain',
           'maximum effort', 'no rest', 'extreme workout']


def main() -> int:
    write = '--write' in sys.argv
    candidates = json.loads(CANDIDATES.read_text(encoding='utf-8'))
    by_id = {a['id']: a for a in candidates['activities']}
    live = json.loads(LIVE.read_text(encoding='utf-8'))
    now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    approved, problems = [], []
    for line in SHEET.read_text(encoding='utf-8').splitlines():
        m = ROW.match(line)
        if not m or m.group(1) not in 'xX':
            continue
        aid, title, desc, minutes, effort, when, suits = m.group(2), m.group(3), m.group(4), int(m.group(5)), m.group(6), m.group(7), m.group(8)
        if aid not in by_id:
            problems.append(f'{aid}: not in the candidates file')
            continue
        contexts = [c.strip() for c in when.split(',') if c.strip()]
        states = [s.strip() for s in suits.split(',') if s.strip()]
        text = ' '.join([title, desc] + contexts + states).lower()
        for b in BLOCKED:
            if b in text:
                problems.append(f'{aid}: contains a blocked term ({b})')
        if not set(contexts) <= CONTEXTS or not contexts:
            problems.append(f'{aid}: unknown or missing "when" tag(s): {sorted(set(contexts) - CONTEXTS)}')
        if not set(states) <= STATES or not states:
            problems.append(f'{aid}: unknown or missing "suits" tag(s): {sorted(set(states) - STATES)}')
        if not 1 <= minutes <= 45:
            problems.append(f'{aid}: minutes should be between 1 and 45')
        entry = dict(by_id[aid])
        entry.update(title=title, description=desc, durationMinutes=minutes, effort=effort, contexts=contexts, targetStates=states)
        entry['review'] = {'status': 'approved', 'evidenceTier': 'lifestyle', 'reviewerRole': 'project_owner', 'reviewedAt': now,
                           'clinicianSignoff': False, 'notes': 'Lifestyle entry reviewed by the project owner for low-pressure use.'}
        approved.append(entry)

    ids = {a['id'] for a in live['activities']}
    titles = {a['title'].lower() for a in live['activities']}
    for a in approved:
        if a['id'] in ids:
            problems.append(f"{a['id']}: already in the live library")
        if a['title'].lower() in titles:
            problems.append(f"{a['id']}: the title is already used in the live library")
        ids.add(a['id'])
        titles.add(a['title'].lower())

    print(f'{len(approved)} ticked row(s); {len(live["activities"])} activities in the live library now.')
    for p in problems:
        print('  PROBLEM', p)
    if problems:
        print('Nothing was changed. Fix the rows above and run it again.')
        return 1
    if not approved:
        print('Nothing is ticked yet.')
        return 0
    if not write:
        print('Dry run. Add --write to merge these:')
        for a in approved:
            print('  +', a['id'], a['title'])
        return 0

    live['activities'].extend(approved)
    LIVE.write_text(json.dumps(live, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    merged = {a['id'] for a in approved}
    candidates['activities'] = [a for a in candidates['activities'] if a['id'] not in merged]
    CANDIDATES.write_text(json.dumps(candidates, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f'Merged {len(approved)}. The live library now has {len(live["activities"])} activities.')
    print('Run `flutter test test/activity_library_test.dart` to check it, then rebuild the app.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
