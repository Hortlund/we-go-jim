# Active Workout Scroll Stability Design

## Problem

Completing an expanded exercise collapses its card and then explicitly scrolls the exercise to the top. Near the end of the workout, the requested alignment cannot be satisfied, so SwiftUI clamps the viewport to the bottom. The passive scroll-position binding also uses a fixed top anchor, and the terminal Cancel section can be persisted as the restore target. Together these behaviors can make the bottom position feel sticky after completion, minimization, or restoration.

## Design

- Automatic exercise collapse will not issue a programmatic scroll. The card may collapse, but the user-owned viewport will remain passive.
- Passive scroll tracking will not specify a fixed anchor. Explicit restoration can continue using the existing `ScrollViewProxy` and top alignment for meaningful workout sections.
- The Cancel section will not be restored as workout context. When it is the tracked target, restoration will resolve to the nearest meaningful preceding content: post-workout cardio when present, otherwise the last exercise, then pre-workout cardio or the workout header.
- Existing focus and keyboard targets retain priority because they identify the field the user was actively editing.

## Scope

This change does not alter card-completion rules, rest timers, workout persistence, or the amount of content shown. It does not add continuous pixel-offset persistence.

## Validation

- Unit tests cover completion presentation choosing collapse without repositioning.
- Unit tests cover mapping the terminal Cancel target to meaningful workout content.
- Existing active-workout scroll and runtime tests remain green.
- Simulator checks cover completing the final exercise and minimizing/restoring near the bottom.
