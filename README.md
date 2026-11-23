# Better Forever Cooldowns

Better Forever Cooldowns extends Blizzard’s Cooldown Manager in World of Warcraft: Forever. Add custom spells, items, and missing-buff reminders from the existing Blizzard settings panel.

## Compatibility mode

Compatibility mode is enabled by default to avoid the native CDM taint/error spam under investigation. It leaves Blizzard's HUD icons, timers, visibility, and layouts untouched. Custom spells, items, and buff reminders append after the last icon in the matching Blizzard row, following its size, scale, spacing, direction, and wrap limit. The custom icons use Blizzard's icon mask, border artwork, and countdown fonts. A custom spell always tracks its spell cooldown rather than an aura duration.

Native-icon overrides (rank pins, ready-only filtering, cooldown-only overlays, Mana Gem greying, dividers, and native buff reminders) are inactive in this mode. Your saved configuration is retained. Add a custom spell or buff to append its tracking to the row. Custom entries append after native entries; native-relative drag positions in the settings panel do not interleave the HUD icons.

`/bfc safe` enables compatibility mode and reloads the UI to clear existing taint. `/bfc advanced` restores native-icon customization and reloads; that path can reproduce the reported taint and has not been verified in-game. Turn off diagnostic logging with `/console taintLog 0` after collecting a log.

## Installation

1. Download the addon ZIP from [GitHub Releases](https://github.com/oliome/BetterCooldownManager/releases). Automatic updates are initially published as beta releases.
2. Extract it and copy the `BetterForeverCooldowns` folder into your WoW installation’s `_forever_/Interface/AddOns/` directory. The `BetterForeverCooldowns.toc` file should be directly inside the copied folder.
3. Enable **Better Forever Cooldowns** in WoW’s AddOns list. Enable Blizzard’s Cooldown Manager in the game settings, then open it with `/cdm` or `/bfc`.

If startup reports that `Options.lua` did not load, reinstall the complete addon folder: it must contain `BetterForeverCooldowns.lua`, `Options.lua`, and `BetterForeverCooldowns.toc` together. Check for an earlier error in `Options.lua` if all three files are present.

## Spells, items, and dividers

- **Essential and Utility Cooldowns.** Enter a spell name or ID and click **Add**. Compatibility mode appends a custom cooldown icon to the row. Advanced mode moves a matching Blizzard entry into the chosen section when available; other spells appear as custom icons.
- **Items.** Enter an item name or ID and click **Add**. Drag a custom item into Essential or Utility to track it on the HUD, or use its right-click **Move to** menu. Item icons show cooldowns and grey out when you have none. Advanced mode also greys out Blizzard’s **Mana Gems** icon when you have no gem.
- **Rank and readiness.** Right-click a Blizzard cooldown entry and use **Better CDM → Rank** when multiple learned ranks are available. **Show only when ready** hides the icon until the addon can confirm that the spell is ready.
- **Cooldown instead of aura duration.** Right-click a spell in Essential or Utility Cooldowns and enable **Better CDM → Show cooldown only**. Its timer then shows the spell cooldown or charge recharge, even while its buff is on you or its debuff is on your target. Disable it to restore Blizzard's normal timer selection.
- **Dividers.** Right-click the Blizzard cooldown entry immediately before the desired divider. Under **Better CDM**, choose **Add divider after this ability**. Use the same menu to remove it.

## Missing-buff reminders

Add a custom entry in **Tracked Buffs** for a missing-buff reminder, then right-click it to configure alternatives. In advanced mode you can also right-click a Blizzard entry and enable **Better CDM → Show only when missing**. Use **Choose alternative buffs…** to select buffs that should also suppress the reminder. The list includes learned helpful spells, helpful buffs previously seen on your character, and Blizzard's **Not Displayed** entries. You can also enter a buff name or spell ID directly. For example, select Brilliance as an alternative for an Intellect reminder, or Mage Armor for an Ice Armor reminder.

**Buffs Blizzard omits.** In the **Tracked Buffs** header, use **Buffs** to add a custom missing-buff reminder, or enter its buff name or spell ID and click **Add**. **Headmaster's Charge** is included in the list before you apply it; you can also enter buff spell ID **18264**. Its reminder tracks that buff independently of Arcane Intellect/Brilliance. Other item buffs become available after you use the item once, and are remembered after expiring and across reloads. Use the applied buff's spell ID when it differs from the item's use spell; this field takes a spell ID, not an item ID. Right-click the custom entry to configure alternatives or remove it.

**Intellect and Brilliance.** Arcane Intellect and Arcane Brilliance automatically count as the same buff for missing reminders, across ranks. Either one suppresses the other's reminder. Additional alternatives remain configurable.

Visible custom buff reminders pack together at the end of the Blizzard buff row without reserving slots for hidden custom reminders. They also appear in Edit Mode for placement. The buff list is built from learned spells, observed buffs, and the Headmaster's Charge preset; it does not enumerate every spell in the game's database. A name or spell ID lets you add an otherwise unlisted buff.

In combat, the addon can use Blizzard’s tracked entry to check whether the main buff is missing. If the game withholds the status of a configured alternative, the reminder stays hidden until absence can be confirmed.

Better CDM’s settings are saved per character.

## Automatic version updates

GitHub checks for new Forever builds hourly and publishes a version bump after the automated checks pass. Install the new release ZIP to update the addon. See [build and update checks](.github/updates.md) for setup and verification details.
