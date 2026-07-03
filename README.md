# Word-Off!

Quickfire word battles for iOS. Two players get the same 9 scrambled letters,
30 seconds to type their best word, best of 7 rounds. Plus Wordle-style daily
challenges with global leaderboards.

## Game rules

### PvP (Quick Match / friend challenge)
- 9 shared letters per round — always an anagram of a real 9-letter word, so a
  full-rack word is guaranteed to exist (racks are also picked to maximize how
  many word lengths are playable)
- 30-second timer starts after the tiles flip and "GO!" appears
- Free typing; invalid words are rejected instantly with feedback so you can
  keep trying; submit locks your word, but you can edit and resubmit until 0:00
- **Scoring:** Scrabble letter values, +1 per letter beyond 4, +5 for using all
  9 letters, +2 for submitting a valid word first
- Invalid word = 0 points; tied round = replay (no repeating your word);
  3 consecutive tied replays = match ends in a tie (doesn't affect W/L)
- 7 rounds max, first to 4 round wins
- Leaving the app mid-round forfeits that round (anti-cheat)
- If matchmaking can't find a human in 15 seconds, you play a hidden AI
  (skill tiers 1–10, believable usernames)

### Daily challenges
- Five puzzles per day: 6, 7, 8, 9, and 10-letter racks
- Each puzzle = 4 racks x 30 seconds, cumulative score
- Everyone in the world gets identical racks (seeded by date)
- Rankings show your rank and percentile per puzzle size
- Free players pick 3 of the 5 puzzles; Premium unlocks all 5
- Playable offline; scores sync to leaderboards when online

### Lives & streaks (free tier)
- 5 lives/day; each PvP game (including rematches) costs 1
- First friend game each day is free
- +1 bonus life per 2 consecutive login days (max +5 at a 10-day streak);
  bonus resets if the streak breaks
- Daily challenges never cost lives

### Monetization
- **Premium** `com.wordoff.premium.monthly` ($5.99/mo): all dailies, unlimited
  PvP, no ads
- **Day Pass** `com.wordoff.dailypass` ($1.99 consumable): same perks until
  local midnight
- Ads deferred until DAU justifies them

## Project structure

```
project.yml              XcodeGen project definition
WordOff/
  App/                   App entry + root routing
  Core/                  Game engine: letters, scoring, dictionary, RNG, AI
  Game/                  Match + daily state machines (view models)
  Services/              Supabase client, lives/streaks, StoreKit, persistence
  Views/                 SwiftUI screens
  UI/                    Theme + shared components
  Resources/words.txt    ENABLE dictionary, filtered to 2-10 letter words
supabase/schema.sql      Database schema (profiles, scores, friends, matches)
```

## Building

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open WordOff.xcodeproj
```

Then run on an iOS 17+ simulator or device.

## Custom sounds

Effects default to built-in iOS system sounds. To use your own, drop audio
files named `whoosh`, `flip`, `tick`, `win`, `lose`, `error`, or `fanfare`
(`.wav`, `.caf`, `.aiff`, `.mp3`, or `.m4a`) into `WordOff/Resources/`, run
`xcodegen generate`, and rebuild — they're picked up automatically.

## Backend setup (optional — app runs fully offline without it)

The app works in **local mode** out of the box: daily puzzles, AI matches,
lives, streaks, and stats all function with no backend. To enable accounts,
leaderboards, and human matchmaking:

1. Create a free project at [supabase.com](https://supabase.com)
2. Run `supabase/schema.sql` in the SQL editor
3. Enable Email and Apple providers under Authentication
4. Set your keys in `WordOff/Services/SupabaseClient.swift` (`SupabaseConfig`)
   or via the `SUPABASE_URL` / `SUPABASE_ANON_KEY` environment variables in the
   Xcode scheme

## App Store setup (for purchases)

In App Store Connect create:
- Auto-renewing subscription `com.wordoff.premium.monthly` at $5.99/month
- Consumable `com.wordoff.dailypass` at $1.99

Until these exist, the paywall shows placeholder pricing and free-tier rules apply.

## Roadmap (post-v1)

- Realtime human-vs-human rounds over Supabase Realtime (schema is ready;
  client currently uses hidden AI opponents for all matches)
- Push notifications for friend challenges (APNs)
- Friends leaderboard tab and country filters
- Ads for free users after games
