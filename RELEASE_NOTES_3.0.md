# Caffeine Toggle 3.0

A tiny native macOS menu-bar app for keeping your Mac awake—with a visual coffee-cup Timer and flexible schedules.

![Caffeine Toggle 3.0 coffee-cup Timer](https://raw.githubusercontent.com/kimiyashar/caffeine-toggle/v3.0/docs/assets/ui/timer-full.png)

## Download and install

1. Download **Caffeine-Toggle-3.0.zip** from the Assets section below.
2. Open the ZIP and drag **Caffeine Toggle** into your **Applications** folder.
3. The first time only, Control-click the app, choose **Open**, then choose **Open** again.

No Xcode or Terminal is needed.

If macOS still blocks the app, open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Caffeine Toggle. This release is signed with an Apple Development certificate but is not yet notarized for automatic Gatekeeper approval.

**Requirements:** Apple Silicon Mac running macOS 26 or later.

## What's new

- Native menu-bar mug: left-click to toggle immediately; right-click or two-finger click for Timer and Schedule.
- A compact coffee-cup Timer that starts full, drains relative to the selected duration, freezes while paused, and becomes completely empty at zero.
- Timer durations from 1 minute through 7 days.
- Four clear scheduling modes: **One Time**, **Every Day**, **Weekdays**, and **Custom** weekday windows.
- A directly attached neutral light-gray panel with a latte-brown main switch.
- Reliable helper lifecycle with exactly one PID-bound `caffeinate` process.
- Migration of existing Caffeine, Timer, and Schedule settings.

## The UI

### Menu-bar states

| Caffeine ON | Caffeine OFF |
|---|---|
| ![Filled Caffeine Toggle mug in the menu bar](https://raw.githubusercontent.com/kimiyashar/caffeine-toggle/v3.0/docs/assets/ui/menu-bar-on.png) | ![Empty Caffeine Toggle mug in the menu bar](https://raw.githubusercontent.com/kimiyashar/caffeine-toggle/v3.0/docs/assets/ui/menu-bar-off.png) |

The mug lives directly in the macOS menu bar beside your system controls. Caffeine Toggle does not install a separate Control Center extension.

### Timer and Schedule panel

| Timer | Schedule |
|---|---|
| ![Coffee-cup Timer](https://raw.githubusercontent.com/kimiyashar/caffeine-toggle/v3.0/docs/assets/ui/timer-full.png) | ![Four Schedule modes](https://raw.githubusercontent.com/kimiyashar/caffeine-toggle/v3.0/docs/assets/ui/schedule-options.png) |

## Safety

An awake Mac can generate heat. Keep it plugged in on a hard, open, ventilated surface—never in a bag, sleeve, bed, or enclosed space. Closed-lid behavior uses a private macOS interface and should be tested on your own Mac before you rely on it.
