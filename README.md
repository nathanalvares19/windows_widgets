# Windows Desktop Custom Widgets

Implementation of custom Windows Desktop Widgets.

## Implementation

### Manchester United Fixture Widget

- Uses [Rainmeter](https://www.rainmeter.net/) for UI and functionality.
- Uses [Manchester United Fixture Feed](https://calendar.google.com/calendar/render?cid=webcal://calendar.google.com/calendar/ical/ov0dk4m6dedaob7oqse4nrda4s%40group.calendar.google.com/public/basic.ics).
- Uses Lua to fetch the feed and load it into the skin.

### System Usage Widget

- Shows stats about CPU and RAM usage.
- Rainmeter default (visually modified)

### Network Widget

- Shows stats about network usage.
- Rainmeter default (visually modified)

### Clock Widget

- Shows time.
- Rainmeter default (visually modified)

### Calendar Widget

- Shows today's Google Calendar events as a departure board.
- Uses Lua to parse the calendar's iCal feed, including recurring events.
- Setup: copy `calendar_widget/Feeds.example.inc` to `Feeds.inc` and paste your Google Calendar *Secret address in iCal format* (Settings and sharing > Integrate calendar) as `GoogleURL`.
