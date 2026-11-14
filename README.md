# battery

Battery stats for your own iPhone, with charging watts, temperatures, history and predictions. Built for the iPhone Duo: every page lays itself out by the width it gets, folded or open, portrait or landscape.

- **Now**: what the battery is doing in one sentence, then level, charger watts (or drain), heat and health, today's level with the forecast ahead, the charger live, and the last few charges.
- **History**: the level over a day, a week or four, use and charge per day, when you charge, how fast it drains at each hour, how fast it charges at each level, and every charge.
- **Health**: maximum capacity and cycles from the Analytics files you share, the capacity it learned from your charges, and the hottest charge.

## What it reads

| | From |
| --- | --- |
| Level, charging, Low Power Mode, heat state | UIKit and powerd |
| Charger watts, volts, amps, watts into the battery | IOHIDEventSystemClient power sensors (private) |
| Battery and chip temperature | IOHIDEventSystemClient temperature sensors (private) |
| Charger kind and wattage | `IOPSCopyExternalPowerAdapterDetails` (private) |
| Health and cycles | an Analytics file you share (Settings › Privacy & Security › Analytics & Improvements › Analytics Data) |

The private APIs make it a development build for your own phone; it can't go on the App Store.

## Predictions

Everything is worked out from the readings it saves (`Sources/Battery/Analysis.swift`):

- **Time left** runs the level forward five minutes at a time at the rate your phone usually drains at each hour of the day, nudged by how this stretch off the charger is going. The band around it comes from how much faster or slower your drains usually run.
- **Time to full** sums the minutes each percent took on past charges, level by level, scaled by how fast this charge is going, and stops at your charge limit when your charges stop there.

## Battery use

It reads every second while on screen. In the background it keeps running only while plugged in, every ten seconds (coarse location updates keep it awake; the fixes are thrown away), and stops the moment you unplug. Off the charger it does nothing unless iOS wakes it for a background refresh or a Shortcuts automation runs **Record Battery** (Automation › Charger › Is Connected / Is Disconnected).

## Build

- `scripts/phone` builds with [xtool](https://github.com/xtool-org/xtool) on Linux, signs on a Mac and publishes to hangar.
- `scripts/shots`, on GitHub's Macs (`.github/workflows/shots.yml`), screenshots every page on the iPhone Duo's four poses, light and dark, with made-up readings (`-demo charging` or `-demo battery`).

## Credits

The private IOKit and IOHID readers are adapted from [ChargeSpeed](https://github.com/cbowns/ios-charging-monitor) by Greg Wilson (MIT). `scripts/devicehub.c` is adapted from [hinge](https://github.com/artemnovichkov/hinge) by Artem Novichkov (MIT).
