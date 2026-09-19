---
name: gold-star-demerit
description:
  Use when the user says "gold star", "gold-star", "⭐", or "demerit" to reward or penalize Claude's
  behavior. Also use when the user asks for the current score, tally, or record.
---

# Gold Star / Demerit Tracker

Make exactly one Bash call, then reply with its stdout verbatim. The script owns the arithmetic and
the file (`~/.claude/gold-star-score.json`) — do not read, compute, or write the tally yourself.

| Trigger                                 | Command                                                  |
| --------------------------------------- | -------------------------------------------------------- |
| "gold star" / gold-star / ⭐            | `~/.claude/skills/gold-star-demerit/star.sh`             |
| "demerit"                               | `~/.claude/skills/gold-star-demerit/demerit.sh`          |
| "score" / "tally" / "how are you doing" | `~/.claude/skills/gold-star-demerit/bump.sh` (read-only) |

Each prints the finished report line, e.g. `⭐ Gold star! Stars: 14, Demerits: 0 → net: 14`. That
line is the whole reply. Never just acknowledge conversationally.

Non-zero exit means the score file is unreadable: report the error, don't repair the file by hand.
