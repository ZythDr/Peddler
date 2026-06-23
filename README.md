# Peddler

Smart, quiet vendor helper for World of Warcraft.  
Peddler automatically flags and sells the junk you don't want—while keeping you in control.

---

## What It Does

- Auto-flags and sells: Poor (grey) items by default.  
- Lets you decide: Optional selling of other qualities and class-unusable gear.  
- Account-wide class filters: Choose which armor and weapon subtypes each class considers wanted.  
- Equipment set protection: Prevents exact bag slots used by Blizzard equipment sets from being flagged or sold.  
- Safe by design: Nothing gets auto-flagged unless you choose it.  
- Manual control: Hold your chosen modifier + right-click to toggle sell (or delete for valueless items).  
- History window: See what was sold, how much you made, and buybacks.  
- Optional deletion: Manually flag unsellable (no vendor price) items for permanent removal—with a confirmation.  
- Setup wizard: Runs once to help you choose your preferences quickly.

---

## Quick Start

1. Install like any other addon (folder named `Peddler` in your AddOns directory).
2. Launch the game and log in.
3. The setup wizard will appear automatically (or use `/peddler setup`).
4. Visit a vendor — flagged items sell automatically.
5. Use `/peddler history` to view your sales.

---

## Core Usage

| Action | How |
|-------|-----|
| Open options | `/peddler config` |
| Re-run setup wizard | `/peddler setup` |
| Show sales history | `/peddler history` |
| Reset manual sell flags | `/peddler reset flags` |
| Reset deletion flags | `/peddler reset delete` |
| Reset history window | `/peddler reset history` |
| Full reset | `/peddler reset all` |
| Help | `/peddler help` |

---

## Manual Flagging

- Modifier + Right-Click an item in your bags:
  - If it has value: Toggles auto-sell.
  - If it has NO vendor price: Toggles delete flag (red coin icon).
- Modifier key is chosen in setup or options (Ctrl / Alt / Shift or combos).
- You can always unmark anything.

---

## Wanted Item Filters

Open `/peddler config`, then select **Peddler > Wanted Items** to edit each class's wanted armor and weapon subtypes.  
These filters are account-wide, so every Warrior uses the same Warrior filter, every Mage uses the same Mage filter, and so on.

Unchecked subtypes are treated as unwanted when **Unwanted Items** auto-selling is enabled.

---

## Equipment Set Protection

Enable **Protect Equipment Set Items** in `/peddler config` to keep items used by Blizzard Equipment Manager sets from being manually flagged or auto-sold.

Protection is based on the exact bag slot referenced by the equipment set, so a duplicate item in another slot can still be flagged.

---

## Deleting Unsellable Items (Optional)

Some items have no vendor value (soulbound clutter, quest leftovers, etc.).  
You may manually mark these for deletion. They are **never** deleted without:
1. You visiting a vendor.
2. You confirming the deletion popup.

No surprises. No auto-delete.

---

## History & Tracking

Open with `/peddler history`:
- See a scrollable list of sales (automatic + manual), buybacks, deletions(by peddler).
- Filter by reason (manual, quality, deleted, etc.).
- Search by name.
- Session profit shown at the bottom.

---

## Icons & Indicators

| Icon Color | Meaning |
|------------|---------|
| Yellow coin | Will be auto-sold at vendor |
| Red coin | Manually flagged for deletion (no value) |

---

## Bag Addon Support

Peddler supports the default Blizzard bags plus compatibility paths for several bag addons.

- DragonUI's Combuctor bags are supported as of v1.4.
- ElvUI bags are supported.
- Bagnon bags are supported.
- Combuctor bags are supported.

---

## Recommended Starting Settings

- Sell: Poor (grey) items
- Also enable: Soulbound-only filtering (keeps BoE safe)
- Enable Unwanted (class unusable) if you trust it
- Leave Common (white) items off unless you really want them gone

You can change any of these later.

---

## Safety Notes

- Nothing rare or epic is sold unless you explicitly enable it.
- Buyback is still possible for normal vendor sales (unless deleted).
- Deletion is permanent — only confirm if you’re sure.

---

## Lightweight & Quiet

No spam. Chat stays clean unless you disable Silent Mode.  
You can still view full details in the history window when you care.

---

## Thanks

Enjoy a cleaner inventory and faster vendor runs.  
Feedback welcome—tweak it to your style!

---
