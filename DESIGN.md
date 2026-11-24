---
name: United Matchday Ticket
description: The next Manchester United fixture printed as a matchday ticket on the desktop.
colors:
  united-red: "rgb(218, 41, 28)"
  ticket-paper: "rgb(250, 250, 248)"
  thermal-ink: "rgb(20, 20, 20)"
  small-print-grey: "rgb(105, 105, 105)"
  perforation-grey: "rgb(150, 150, 146)"
  stub-white: "rgb(255, 255, 255)"
typography:
  display:
    fontFamily: "Barlow Condensed"
    fontSize: "30pt"
    fontWeight: 700
  headline:
    fontFamily: "Barlow Condensed"
    fontSize: "24pt"
    fontWeight: 700
  title:
    fontFamily: "Barlow Condensed"
    fontSize: "18pt"
    fontWeight: 600
  body:
    fontFamily: "Barlow"
    fontSize: "10pt"
    fontWeight: 500
  label:
    fontFamily: "Barlow"
    fontSize: "8pt"
    fontWeight: 600
    letterSpacing: "0.6"
rounded:
  ticket: "6px"
  notch: "8px"
spacing:
  sheet-inset: "8px"
  body-margin: "28px"
  stub-center: "306px"
components:
  ticket-body:
    backgroundColor: "{colors.ticket-paper}"
    textColor: "{colors.thermal-ink}"
    rounded: "{rounded.ticket}"
    width: "344px"
    height: "168px"
  ticket-stub:
    backgroundColor: "transparent"
    textColor: "{colors.thermal-ink}"
    width: "91px"
  ticket-stub-matchday:
    backgroundColor: "{colors.united-red}"
    textColor: "{colors.stub-white}"
    width: "91px"
  issuer-line:
    textColor: "{colors.united-red}"
    typography: "{typography.label}"
---

# Design System: United Matchday Ticket

Scope: this system governs the Man United fixtures widget only (`man_united_fixtures/UnitedMatchV2.ini`). The system, network and clock widgets stay utilitarian and do not inherit it. Values are expressed as the Rainmeter skin uses them: RGB triples, point sizes, pixel coordinates on a 360 x 184 canvas.

## Overview

**Creative North Star: "The Matchday Ticket"**

The next fixture is a printed ticket: white stock, black thermal print, one line of club red. The body names the match; the stub, behind a punched tear line, holds when. It refuses the centred crest-time-crest card the category defaults to.

The surface is quiet and paper-flat so it sits on the wallpaper without competing. Hierarchy comes from type size and the body/stub split, not from boxes, tiles or colour fields. Red is rationed; it appears only on the issuer line, and across the whole stub on matchday.

**Key Characteristics:**
- One sheet of ticket stock with two semicircular perforation notches.
- Body left (who and where), stub right (when), split by a dotted tear line.
- Condensed bold print for the match, small tracked caps for the fine print.
- Red as the issuer's mark, never decoration.
- Matchday inverts the stub to solid red.

## Colors

Paper and carbon print with a single club accent.

### Primary
- **United Red**: the issuer line (competition / home-away) and, on matchday only, the stub fill. Nothing else.

### Neutral
- **Ticket Paper**: the sheet fill.
- **Thermal Ink**: opponent name, initials fallback, United row name, stub day number, kickoff and countdown.
- **Small-Print Grey**: stub weekday and month at rest.
- **Perforation Grey**: the punched tear-line dots.
- **Stub White**: all stub text on matchday.
- Sheet edge stroke is black at alpha 40; the body's closing hairline is black at alpha 28.

### Named Rules
**The Issuer's Mark Rule.** Red is the issuing club's ink. It prints one line of the body and, on matchday, the whole stub; it never fills a tile, pill or highlight.

**The Matchday Inversion Rule.** On the day of the match the stub fills red and its text turns white (`GetStubFill/Ink/Sub`). This is the only state change in the system.

## Typography

**Display Font:** Barlow Condensed (Bold 700, SemiBold 600), bundled in `Fonts\`
**Body Font:** Barlow (Medium 500, SemiBold 600), bundled in `Fonts\`

**Character:** Condensed bold for what a ticket prints large, plain Barlow for the fine print. Both are bundled as LocalFonts; no system face stands in.

### Hierarchy
- **Display** (700, 30pt, stepping to 24pt at 12-15 characters and 20pt above): the opponent name. Size steps by length so the name never clips inside its 170px box.
- **Headline** (700, 24pt): the stub day number.
- **Title** (600, 18pt): kickoff time (24h, or TBC).
- **Second row**: "Man United" in the opponent's exact style and size (both rows use GetOpponentSize). The connector is Barlow Condensed 600 13pt Grey, set in the name column between the rows: "v" away, "at" home, so the names stack top to bottom.
- **Label** (600, 8pt, uppercase, character spacing 0.6): issuer line, stub weekday and month. The countdown uses the same uppercase tracked style at 10pt.
- **Fallback initials** (Barlow Condensed 700, 16pt, ink): shown centred in the crest box only when no crest image exists.

### Named Rules
**The Printed Fine Print Rule.** Small text is uppercase, tracked 0.6, Barlow 600. Big text is Barlow Condensed. There is no third family.

## Layout

A fixed 344 x 168 sheet inset 8px in the window. The perforation sits at x 260: body is 252px wide, stub 92px. Body content hangs off a 26-28px left margin: opponent crest 40px at (26,22), name centred on y 42 from x 82; connector left-aligned at x 84 on y 76; United crest 40px at (26,90), name centred on y 110 from x 82 (a mirror of the opponent row); hairline at y 142 (x 28-240), issuer line on y 159. Stub elements are centre-aligned on x 306 and stack weekday 34, day 64, month 92, kickoff 124, countdown 153. Every text field clips (`ClipString=1`) to its box.

## Elevation & Depth

Flat. The ticket is one plane: no shadows, glows or bevels. The only edge is a 1px black stroke at alpha 40 around the sheet, which separates paper from wallpaper. Depth is suggested by the cut notches and tear line, physical ticket features, not by lighting.

## Shapes

Softly cornered stock (6px radius) with two 8px-radius semicircular notches cut from top and bottom edges at the perforation. The tear line is round dots (2px stroke, dashes 0.1/3.5, round caps), not a dash. The matchday stub fill matches the sheet's right corners and is clipped by the same notches.

## Components

### Ticket Body
Paper sheet, ink print. Crest + opponent name, the connector, then United crest + name mirroring the opponent row, a hairline, and the issuer line closing the body.

### Ticket Stub
Transparent at rest so the sheet shows through; weekday and month in small-print grey, day/kickoff/countdown in ink. Countdown reads `IN N DAYS`, `TOMORROW`, `TODAY`, or `LIVE`.

### Matchday Stub
Same stub filled United Red, all text Stub White.

### Issuer Line
Competition name plus `  /  HOME` or `  /  AWAY`, uppercase label style in United Red, bottom of the body.

## Do's and Don'ts

### Do:
- **Do** keep red to the issuer line and the matchday stub.
- **Do** print the opponent as the largest thing on the ticket, stepping 30/24/20pt by name length.
- **Do** keep the perforation as round punched dots between two notches.
- **Do** use only the bundled Barlow and Barlow Condensed faces.
- **Do** show TBC for date-only fixtures and keep every field clipped to its box.

### Don't:
- **Don't** add tiles, pills, glows or shadows to the ticket.
- **Don't** centre the layout into a crest-time-crest card.
- **Don't** add extra labels or boxes; each line on the ticket carries data.
- **Don't** apply this system to the system, network or clock widgets.
