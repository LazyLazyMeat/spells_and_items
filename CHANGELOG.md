# Changelog

All notable changes to this project.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-11-16

### Added
- Item compendium: list view with filters by type, rarity and attunement.
- Item detail page with description, price, rarity variants and additional info.
- Attunement tracker: 3 base slots, "Mysterious Fusion" checkbox, and "Artificer" checkbox with a 1–3 slider; toast notifications when occupied slots are removed.
- "+ Add to attunement" button on item card and in item list.
- Item parser: support for prototypes, rarity variants, and attunement with notes.

### Changed
- Spells list route: `#/` → `#/spells`.
- Web packer: `Pack-SpellWeb.ps1` → `Pack-DataWeb.ps1` (now bundles both `spells.js` and `items.js`).
- `run.bat`: unified two-digit menu (11–19 for spells, 21–29 for items).

## [1.1.0] - 2026-11-01

### Added
- Spell deck tracker: dynamic buckets with two sections (cantrips + leveled spells), global spell uniqueness, optional "Other" bucket.
- "+ Add to deck" button on spell card.

## [1.0.0] - 2026-10-15

### Added
- Spell compendium: list view with filters (level, school, class, ritual, concentration).
- Spell detail page.
- Spell parser and download scripts for dnd.su.
- Static site packaging into a zip archive.