# Product

<!-- impeccable:product-schema 1 -->

## Platform

windows-desktop (Rainmeter skins; not one of web/ios/android/adaptive)

## Users

Just the owner. These widgets sit on their personal Windows 11 desktop and get read in a glance, often from across the room. Nobody else installs them.

## Product Purpose

Four desktop widgets: Man United fixtures, system usage (CPU/RAM), network usage and a clock. Each one answers a single question in a single look: when is the next United match, how loaded is the machine, how much traffic is there, what time is it.

## Positioning

A personal, hand-tuned set built for one desktop. It is not a general-purpose skin pack.

## Operating Context

- Rainmeter loads the skins from `OneDrive\Documents\Rainmeter\Skins\`. The repo holds copies of them.
- Fixtures come from a public Google Calendar ICS feed that is downloaded hourly. The last good copy is cached and used whenever a download fails.
- Crests are matched to clubs through `@Resources\ClubCrests.lua` (ESPN team IDs). Initials stand in when a club has no crest.

## Capabilities and Constraints

- Rainmeter only: INI, Lua and Shape/String/Image meters. No web or Electron runtime.
- The Google Calendar ICS feed stays the fixtures data source, along with the last-good cache fallback.
- Kickoff times show in the viewer's local timezone. A date-only fixture is shown exactly as published, with the kickoff marked as TBC.
- The card footprint is not fixed across the set.

## Brand Commitments

- The fixtures widget may have its own identity, built around Manchester United (club red, crests). The system, network and clock widgets stay utilitarian.

## Evidence on Hand

- Club crests: `@Resources\Logos\Clubs\` in the installed skin.
- No other assets.

## Product Principles

1. Readable at a glance: one key fact per widget, legible from a distance.
2. Never show stale or invented data. Fall back to the cache, and say so when there's nothing usable.
3. Fit quietly on the desktop. The widgets support the wallpaper and don't compete with it.
