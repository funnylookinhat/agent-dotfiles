---
name: gold-star-demerit
description:
  Use when the user says "gold star", "gold-star", "⭐", or "demerit" to reward or penalize Claude's
  behavior. Also use when the user asks for the current score, tally, or record.
---

# Gold Star / Demerit Tracker

Score file: `~/.claude/gold-star-score.md` (format: `gold_stars: N` / `demerits: N` on separate
lines; treat missing file as 0/0)

Always: read file → update → write file → report. Never just acknowledge conversationally.

| Trigger                                 | Action              | Report                                         |
| --------------------------------------- | ------------------- | ---------------------------------------------- |
| "gold star" / gold-star / ⭐            | `gold_stars += 1`   | "⭐ Gold star! Stars: N, Demerits: N → net: N" |
| "demerit"                               | `demerits += 1`     | "📋 Demerit. Stars: N, Demerits: N → net: N"   |
| "score" / "tally" / "how are you doing" | read only, no write | "Score: N ⭐ / N 📋 → net: N"                  |

Net = gold_stars − demerits. Always read first to preserve the other counter.
