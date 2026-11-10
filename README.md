# ແບ່ງກຸ່ມ BF124 (class group picker)

Single-page app (`index.html`) on Supabase. Students pick their name, enter a personal PIN, then choose a group; the admin page (`#/admin`) creates activities, locks, random-fills and exports.

- `index.html` – the app (uses a Supabase publishable key, safe to be public)
- `migration_pins.sql` – per-student PIN tables and functions
- `demo.html` – static mock-up with fake data

The base schema and the student roster are intentionally not in this repo (they hold real names and student IDs).
