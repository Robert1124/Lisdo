# Lisdo Design Guide

## Scope

This document covers only the native app and extension experience:

- iPhone app
- Mac app
- Widget Extension
- Live Activity
- Share Extension
- macOS menu bar / floating capture shell

Do not use this document to implement a website, landing page, pricing page, or marketing site. The website sections inside `Design/Lisdo standalone.html` are out of scope.

## Source Of Truth

Primary source:

- `Design/Lisdo standalone.html`, app and extension sections only.

Secondary visual reference:

- `Design/Lisdo — print.pdf`, when useful for static layout review.

## Design Principles

Lisdo should feel:

- calm;
- monochrome;
- native to Apple platforms;
- quiet about AI;
- work-oriented;
- draft-first.

The UI should not feel like a playful gamified todo app or a SaaS landing page. The product should feel like a focused inbox where messy captures become clear drafts.

AI should be present but understated. Use draft cards, sparkle chips, shimmer, and review affordances. Do not use large gradients, glowing AI panels, decorative color blobs, or hype-heavy copy.

## Visual Tokens

### Color

```text
Surface:   #FFFFFF
Surface 2: #FAFAF9
Surface 3: #F4F4F2
Divider:   #E5E5E5
Ink 1:     #0E0E0E
Ink 2:     #2C2C2E
Ink 3:     #6E6E73
Ink 4:     #A1A1A6
Ink 5:     #C7C7CC
Ink 7:     #EFEFEF
OK:        #2F7D4F
Warn:      #B5651D
Info:      #355C8A
```

Use near-black as the primary accent. Status colors should be low saturation and rare.

### Type

Use the Apple system type stack:

```text
-apple-system / SF Pro Text / SF Pro Display
```

Approximate scale:

```text
Display:    36 / 600
Title:      22 / 600
Card title: 17 / 600
Body:       14 / 400
Meta:       12 / 400
Eyebrow:    11 / 500 / uppercase / +0.08 tracking
```

### Radius And Elevation

Use soft but not bubbly corners:

```text
xs: 6
sm: 10
md: 14
lg: 20
xl: 28
```

Use almost-flat elevation. Cards should rely more on spacing, borders, and subtle surfaces than strong shadows.

## Core Components

### Task Card

Task cards represent confirmed todos. They should be calmer and more solid than draft cards.

Required content:

- checkbox;
- category label;
- due/scheduled metadata when available;
- title;
- optional summary.

### Draft Card

Draft cards represent AI-generated but unapproved work. They must be visually distinct from final tasks.

Required treatment:

- dashed border;
- lightly frosted/tinted surface;
- `Draft` or sparkle chip;
- suggested category;
- title;
- summary;
- checklist/items;
- Save/Edit/Revise actions.

Draft cards should never look final.

### Pending Queue Item

Pending items represent captures that have not become drafts yet.

States:

- waiting for Mac;
- processing;
- ready to review;
- failed;
- retry pending.

Each state should include human-readable status. Avoid generic spinners with no explanation.

### Capture Surface

Capture surfaces should support the full product shape even when a source is not wired yet.

MVP 1 real sources:

- text/paste;
- image import;
- Vision OCR.

MVP 1 placeholder sources:

- voice;
- screenshot/share sheet;
- Mac region capture;
- links if not yet wired.

Placeholder actions must be disabled or clearly marked as coming in a future MVP.

### Buttons And Controls

Use native-feeling controls:

- primary pill for the main action;
- ghost buttons for secondary actions;
- icon buttons for compact actions;
- segmented/pill category selection;
- calm circular checkboxes.

Avoid oversized marketing buttons inside app surfaces.

## iPhone App Structure

Primary navigation:

- Inbox
- Categories
- central capture action
- Plan
- You/Settings

### Inbox

MVP 1 must show:

- draft cards ready for review;
- pending placeholder items;
- today tasks;
- saved todos.

### Draft Review

MVP 1 must support:

- viewing source text/OCR text;
- suggested category;
- manual category switch;
- title edit;
- summary edit;
- checklist edit;
- due/time display or edit if model provides it;
- ask-AI-to-revise placeholder or basic text entry;
- save as todo.

### Quick Capture

MVP 1 must support:

- paste/type text;
- image import;
- organize into draft.

Voice/photo/screenshot/link controls can exist as placeholders if not fully wired.

### Categories

MVP 1 must support:

- active categories;
- smart lists placeholders;
- category counts;
- category detail navigation for todos.

### Plan

MVP 1 can show the Plan/calendar UI shell with sample or real due-date todos if cheap. Advanced scheduling and full planning behavior belongs to MVP 3/4.

## Mac App Structure

Mac should use a work-oriented layout:

- sidebar with Inbox/Drafts/Today/Plan/From iPhone;
- category section;
- main inbox triage area;
- search field;
- capture button;
- draft cards with Save/Edit/Revise.

The menu bar/floating capture shell should exist in MVP 1. Real clipboard/region/voice processing can be completed in MVP 2.

## Extensions

### Widget Extension

MVP 1 must include a real Widget target with static/sample or simple real data states. It must not be an empty placeholder.

Widget types from the prototype:

- small: today's focus;
- medium: inbox/draft summary;
- large: today + active task + quick capture style surface.

Interactive behavior can wait until MVP 3.

### Live Activity

MVP 1 must include a real ActivityKit/Live Activity shell through the Widget Extension configuration. It can use sample active-task data. Real active task progress belongs to MVP 3.

### Share Extension

MVP 1 must include the target and basic UI shell. Actual ingestion into the capture pipeline belongs to MVP 2.

## Placeholder Rule

Every placeholder must answer:

- what this feature will do;
- why it is not active yet;
- when it is planned;
- what state the captured item is in, if applicable.

Good placeholder:

```text
Waiting for Mac processing
This capture will be organized when your Mac processes pending items in MVP 2.
```

Bad placeholder:

```text
Unfinished note
Generic coming-soon label with no milestone
Empty page with no state explanation
```

## Accessibility

- Preserve dynamic type where possible.
- Maintain high contrast.
- Do not rely on color alone for state.
- Use clear labels for draft, pending, failed, and saved states.
- Keep tap targets native-sized.
