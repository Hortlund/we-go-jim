# Exercise Catalog Expansion Design

## Goal

Expand WGJ's bundled exercise catalog with common missing movements, make "Dumbbell Bench Press" a first-class displayed exercise, and repair equipment metadata that currently prevents reliable filtering. Preserve all existing workout, template, and history references.

## Scope

This change is limited to the local, versioned exercise seed and focused catalog tests. It does not change SwiftData models, views, workout behavior, CloudKit backup, or image handling.

### New exercises

Add these 16 curated exercises with stable seed UUIDs and sequential remote IDs:

| Exercise | Category | Equipment | Primary muscle | Notes |
| --- | --- | --- | --- | --- |
| Dumbbell Curl | Arms | Dumbbells | Biceps | Standard bilateral curl; distinct from the existing alternating curl |
| Dumbbell Skull Crusher | Arms | Dumbbells, Bench | Triceps | Alias only to the equivalent lying dumbbell triceps-extension name |
| Dumbbell Overhead Triceps Extension | Arms | Dumbbell | Triceps | Two-hand, single-dumbbell movement; distinct from the existing single-arm entry |
| Dumbbell Pullover | Back | Dumbbell, Bench | Back | Chest and triceps are secondary |
| Dumbbell Romanian Deadlift | Legs | Dumbbells | Hamstrings | Glutes and back are secondary |
| Bodyweight Squat | Legs | Bodyweight | Quadriceps | "Air Squat" is a true synonym |
| Bodyweight Lunge | Legs | Bodyweight | Quadriceps | Glutes and hamstrings are secondary |
| Lateral Lunge | Legs | Bodyweight | Quadriceps | "Side Lunge" is a true synonym; glutes and adductors are secondary |
| Crunch | Core | Bodyweight | Abs | Basic floor crunch |
| Sit Up | Core | Bodyweight | Abs | Basic floor sit-up |
| Bicycle Crunch | Core | Bodyweight | Abs | Rotating bodyweight core movement |
| Lying Leg Raise | Core | Bodyweight | Abs | Floor-based movement, distinct from hanging leg raise |
| Kettlebell Clean | Conditioning | Kettlebell | Glutes | Hamstrings, traps, and shoulders are secondary |
| Kettlebell Snatch | Conditioning | Kettlebell | Shoulders | Glutes, hamstrings, and traps are secondary |
| Hiking | Cardio | Outdoor | Quadriceps | Uses the existing walk/run tracking profile; glutes and calves are secondary |
| Swimming | Cardio | Pool | Back | Uses the existing time-only tracking profile; shoulders and chest are secondary |

Each entry includes concise technique instructions and the same WGJ bundled attribution used by the current curated catalog.

### Canonical naming and aliases

Rename the existing displayed exercise "Dumbbell Flat Press" to "Dumbbell Bench Press" while preserving its current `seed-dumbbell-flat-press` UUID and remote ID. This keeps saved workouts, templates, and history connected. Retain "Dumbbell Flat Press" and "DB Press" as search aliases.

Aliases are limited to genuine synonyms or unambiguous abbreviations. They must not collapse equipment variants, unilateral/bilateral variants, or materially different techniques into one result. Searching an alias returns the canonical exercise row whose displayed name accurately describes the workout.

Audit all existing aliases under the same rule. In particular:

- remove `Treadmill Walk` from Incline Treadmill Walk because Treadmill Walk is already a distinct canonical exercise;
- remove `Wide Grip Pulldown` from Lat Pulldown because Wide Grip Lat Pulldown is already a distinct canonical exercise;
- correct the existing `seed-reverse-curl` row to the canonical name `Barbell Reverse Curl` with `Barbell` equipment, preserving its UUID and remote ID, because a separate canonical EZ Bar Reverse Curl already exists;
- allow shared generic activity searches such as `Run` or `Walking` only when the results remain visibly distinct canonical choices such as Outdoor Run and Treadmill Run.

Automated validation rejects any alias that exactly matches a different canonical exercise name. Semantic alias review remains explicit because equipment, stance, grip, and unilateral/bilateral equivalence cannot be inferred reliably from strings alone.

### Existing equipment metadata

Populate the currently empty equipment field on all 24 affected chest exercises. Use only equipment already implied by each movement, such as `Barbell,Bench`, `Dumbbells,Bench`, `Cable`, `Machine`, `Bodyweight`, or `Dip Station`. This restores correct equipment filtering without creating new exercise identities.

## Data and upgrade behavior

- Increment the seed version from 5 to 6 and update `generatedAt`.
- Assign new remote IDs 1231 through 1246 without reusing an existing ID.
- Give every new entry a unique, stable `seed-...` UUID.
- Existing installs re-import because of the version bump. The current UUID-based upsert updates existing seed rows and inserts the new rows.
- Custom exercises remain untouched because seed import only removes stale non-custom seed rows.
- The Dumbbell Bench Press rename retains the existing UUID, so references remain stable.
- Seed import remains local and occurs through the existing catalog synchronization boundary.

## Validation and error handling

The existing loader continues to reject malformed JSON through decoding errors, and the existing synchronization state records import failures. No new runtime error path is required.

Automated validation will cover:

- seed decoding succeeds at version 6;
- exercise UUIDs and remote IDs are unique;
- all 16 expected canonical entries exist with their required category, equipment, muscle mappings, and cardio profiles;
- Dumbbell Bench Press uses the previous stable UUID and has only accurate aliases;
- Barbell Reverse Curl uses its previous stable UUID and no longer points to EZ Bar equipment;
- no alias exactly matches another exercise's canonical name;
- no curated exercise has an empty equipment field;
- importing version 6 over an older catalog updates the stable press row and inserts the new rows without changing custom exercises.

## Non-goals

- Adding specialty variations merely to increase catalog size
- Adding or sourcing exercise images
- Changing exercise picker UI or search ranking
- Migrating saved references to new UUIDs
- Adding new cardio tracking-profile types
- Changing CloudKit or backup behavior
