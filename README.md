# FactRead

FactRead is an offline facts reading app designed for people who enjoy learning something interesting in a simple, calm, book-like experience.

The app lets users swipe through curated facts across multiple categories without needing a backend, database, login, or internet connection for the reading experience. Facts are bundled directly inside the app as local JSON files, which makes the app fast, reliable, and lightweight.

## App Overview

FactRead focuses on one clear experience: open the app, swipe, and read interesting facts.

It is built to feel closer to a digital pocket book than a noisy content feed. The interface is minimal, readable, and distraction-free, with smooth page navigation, reading themes, bookmarks, voice support, and reminders.

## Features

- Offline fact reading
- Local JSON-based fact storage
- No backend dependency for facts
- No login or account required
- Fast app launch and fact loading
- Category-based reading
- Swipe-based page reading
- Resume from last read page
- Book-like page experience
- Page text typing animation
- Custom reading themes
- Font and appearance customization
- Voice reading/listen feature
- Bookmark support
- Reading reminders
- Developer website link
- Ad-supported monetization with Google AdMob

## Categories

FactRead includes facts across multiple categories:

- Science
- Space
- Nature
- Technology
- Psychology
- History
- Human Body
- Ocean
- Animals
- Movies

Each category has its own local JSON file, making future editing and content updates easier.

## Data Source

FactRead does not fetch facts from Firebase, APIs, or any remote database.

The facts are stored offline inside the app bundle as local JSON files. Each category has a separate JSON file located in the app project under the facts/content folder.

The app reads these local JSON files at runtime and displays only the bundled facts.

## Content Updates

Because FactRead is an offline app, new facts are added by updating the local JSON files and releasing a new app version.

Typical update flow:

1. Add or edit facts in the category JSON files.
2. Build and test the app.
3. Increase the app version/build number.
4. Submit the new version to the App Store.

This keeps the reading experience reliable and avoids backend limits, network failures, or database cost issues.

## Fact Format

Each fact includes basic fields such as:

- Category
- Title
- Body
- Language code
- Display order
- Active status

Example structure:

```json
{
  "category": "Science",
  "title": "Light Travels Extremely Fast",
  "body": "Light moves at about 299,792 kilometers per second in a vacuum. That speed is so high that sunlight reaches Earth in roughly eight minutes.",
  "language_code": "en",
  "languageCode": "en",
  "order": 1,
  "isActive": true
}
