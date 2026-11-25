# SoundMind AI - AI Context

> This document is the permanent project memory for every AI assistant working on this project.
> Read this file before making any changes.
> Never redesign the project. Continue from the existing implementation.

---

# PROJECT

Name:
SoundMind AI

Framework:
Flutter

Platform:
Android First

Language:
Dart

Current Development Style:
Production Quality

Project Status:
Under Active Development

---

# PROJECT VISION

SoundMind AI is a premium AI-powered offline-first music player.

The goal is NOT to build another simple music player.

The goal is to build one of the best local music experiences possible.

The inspiration comes from

• Spotify
• Apple Music
• YouTube Music
• Nothing OS
• Samsung Music
• Poweramp
• BlackPlayer EX

The app must feel modern, intelligent, premium and smooth.

---

# DESIGN RULES

Never redesign existing UI.

Preserve

• Colors
• Typography
• Glass Effects
• Theme
• Layout
• Branding
• Animations
• Logo

Only extend existing designs.

Every new component must match the current visual language.

---

# DEVELOPMENT RULES

Always write production-ready code.

Never create placeholder UI.

Never generate fake AI.

Never generate fake recommendations.

Never use dummy data unless explicitly requested.

Reuse existing

• Widgets
• Helpers
• Constants
• Theme
• Components

Avoid duplicate code.

Keep performance optimized.

Avoid unnecessary rebuilds.

Keep scrolling smooth.

Follow Flutter best practices.

---

# CURRENT ARCHITECTURE

Foundation Refactor Completed.

Project contains

core/
constants/
helpers/
widgets/
theme/

Reusable widgets already exist.

Business logic has started moving outside UI.

Continue using this architecture.

Do not move logic back into widgets.

---

# MUSIC LIBRARY

Primary source:

AudioLibraryService

Device audio must always be preferred.

Never replace real device data with placeholders.

---

# CURRENT FEATURES

Completed

✓ Home Page Foundation
✓ Dynamic Categories
✓ Collections
✓ Popular Rail
✓ Quick Actions
✓ Loading State
✓ Permission State
✓ Empty State
✓ Glass Components
✓ Theme System
✓ Shared Constants
✓ Shared Widgets

---

# NOT YET IMPLEMENTED

Real Playback

Playback Queue

Mini Player

Search Integration

Favorites

Recently Played

History

Equalizer

Bluetooth Controls

Lockscreen Controls

Notification Controls

Background Playback

Lyrics

AI Classification

Online Music

Download Manager

Cloud Sync

Settings Functionality

Storage Insights

Smart Recommendations

---

# CODING RULES

Modify the minimum number of files.

Never rewrite working code.

Prefer extending existing widgets.

Never remove existing functionality.

Always keep backward compatibility.

---

# RESPONSE RULES

Do not explain architecture unless requested.

Do not produce long reports.

Return

1. Files Modified

2. New Files Created

3. Short Summary

Maximum 20 lines.

---

# CURRENT PHASE

The project is currently improving the Home Page.

Only implement the requested feature.

Do not modify unrelated screens.

---

# FUTURE ROADMAP

After Home Page

Search

Player

Library

Settings

Audio Engine

AI Features

Online Features

Performance

Production Release

---

# YOUTUBE SEARCH (updated 25 Nov 2026)

Search runs through `lib/services/innertube_search.dart` — the official
Innertube `youtubei/v1/search` JSON API (the same API YouTube's own web
client uses), NOT through HTML scraping.

Why: `youtube_explode_dart`'s search scrapes the `/results` HTML page and
parses `ytInitialData` out of it. YouTube keeps changing that page (new
layouts, consent / bot walls for stale user-agents, region-dependent
markup), so HTML scraping is the first thing to break after a YouTube
update. The old HTML path is kept as a fallback inside
`YoutubeService.searchVideos` / `searchBrowse` — Innertube first, HTML
search only if Innertube throws.

Rules for this file:

- One bad `videoRenderer` must never fail a whole search — parse
  defensively, skip malformed items.
- Continuation items arrive wrapped in `itemSectionRenderer` (same as the
  first page) — unwrap before parsing videos.
- `ChannelId()` throws on an invalid id — skip the item, never fake an id.
- If YouTube rejects the WEB client, bump `_clientVersion` in
  `innertube_search.dart` first.
- Verified live 25 Nov 2026: 12 real queries (desi + English + Urdu) all
  returned 13–20 videos; pagination to page 3 works; gibberish query does
  not crash (YouTube returns fallback results).

---

# IMPORTANT

If a requested feature cannot be implemented because the backend does not exist,

do NOT fake it.

Either

• hide the feature

or

• prepare the UI until the backend is implemented.

Production quality is more important than feature quantity.

End of AI Context.