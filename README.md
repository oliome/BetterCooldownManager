# Better Forever Cooldowns

Better Forever Cooldowns extends Blizzard’s Cooldown Manager in World of Warcraft: Forever. Add spells and items, choose which spell rank an icon tracks, and organize cooldowns from the existing Blizzard settings panel.

## Installation

1. Download the repository ZIP from GitHub using **Code → Download ZIP**.
2. Extract it and copy the inner `BetterForeverCooldowns` folder into your WoW installation’s `_forever_/Interface/AddOns/` directory. The `BetterForeverCooldowns.toc` file should be directly inside the copied folder.
3. Enable **Better Forever Cooldowns** in WoW’s AddOns list. Enable Blizzard’s Cooldown Manager in the game settings, then open it with `/cdm` or `/bfc`.

## Spells, items, and dividers

- **Essential and Utility Cooldowns.** Enter a spell name or ID and click **Add**. The addon moves a matching Blizzard entry into the chosen section when available. Other spells appear as custom icons you can drag into position.
- **Items.** Enter an item name or ID and click **Add**. Drag a custom item into Essential or Utility to track it on the HUD, or use its right-click **Move to** menu. Item icons show cooldowns and grey out when you have none. The addon also greys out Blizzard’s **Mana Gems** icon when you have no gem.
- **Rank and readiness.** Right-click a Blizzard cooldown entry and use **Better CDM → Rank** when multiple learned ranks are available. **Show only when ready** hides the icon until the addon can confirm that the spell is ready.
- **Dividers.** Right-click the Blizzard cooldown entry immediately before the desired divider. Under **Better CDM**, choose **Add divider after this ability**. Use the same menu to remove it.

## Missing-buff reminders

Right-click a Blizzard entry in **Tracked Buffs**, then enable **Better CDM → Show only when missing**. Use **Choose alternative buffs…** to select entries from **Not Displayed** that should also suppress the reminder. For example, add Mage Armor as an alternative for an Ice Armor reminder.

In combat, the addon can use Blizzard’s tracked entry to check whether the main buff is missing. If the game withholds the status of a configured alternative, the reminder stays hidden until absence can be confirmed.

Better CDM’s settings are saved per character.
