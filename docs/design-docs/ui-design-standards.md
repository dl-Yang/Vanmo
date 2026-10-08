# UI Design Standards

**Status:** Accepted  
**Last reviewed:** 2026-09-30  
**Update trigger:** A professional UI rule, the `ui-ux-pro-max` workflow, or a platform visual convention changes.

This is the harness standard for Vanmo UI quality. It requires the `ui-ux-pro-max` skill and records the general rules that apply to iOS and macOS SwiftUI. It does not replace a platform Figma frame or an existing token.

## Authority Order

Use these sources in order. A lower source must not override a higher one.

1. The correct platform Figma frame for layout, spacing, type, color, radius, shadow, icon, motion, and states.
2. Existing implementation: `Vanmo/Shared/Extensions/Color+Vanmo.swift`, `VanmoMac/UI/DesignSystem/MacDesignTokens.swift`, shared components, system controls, and approved assets.
3. This document.
4. A live `ui-ux-pro-max` search. Use it to check quality and to brief a missing Figma screen. Do not adopt its palette, web font, or web icon set as Vanmo tokens.

If the required screen or state is absent from Figma, design it in the matching platform file before coding it. See [`.cursor/skills/figma-design-fidelity/SKILL.md`](../../.cursor/skills/figma-design-fidelity/SKILL.md).

## Required Skill

Before designing, building, reviewing, fixing, or restyling UI, read [`.cursor/skills/ui-ux-pro-max/SKILL.md`](../../.cursor/skills/ui-ux-pro-max/SKILL.md) and run its search from the repository root. `--design-system` does not take a stack. Use `--stack swiftui` only on a later implementation search. Do not follow the skill's web delivery list: Heroicons, Lucide, Tailwind, `cursor-pointer`, or Google Fonts.

1. State the product, platform, and style in the query: personal video player, media library, iOS or macOS, plus the keywords in the request and the matching Figma frame.
2. Generate a design-system recommendation:

   ```bash
   python3 .cursor/skills/ui-ux-pro-max/scripts/search.py \
     "video player media library native apple dark" \
     --design-system -p "Vanmo" -f markdown
   ```

   Adjust the query to the screen. Keep `--design-system`.
3. Add a domain or stack search only when the first result does not cover the decision:

   ```bash
   python3 .cursor/skills/ui-ux-pro-max/scripts/search.py "animation accessibility loading" --domain ux
   python3 .cursor/skills/ui-ux-pro-max/scripts/search.py "layout navigation list form" --stack swiftui
   ```

4. Do not pass `--persist`. A generated `design-system/MASTER.md` is not a second visual source of truth.
5. When a Figma frame exists, implement that frame. Use the search to catch missing states, weak contrast, layout shift, and accessibility gaps.
6. When a Figma frame is missing, use the search to brief the new Figma screen, then implement the accepted frame.

## General Specifications

### Components

- Prefer system controls for buttons, navigation bars, sheets, forms, lists, and progress.
- On iOS 26 and macOS 26, prefer the system Liquid Glass treatment where the platform provides it. Keep a compatible appearance on the older versions Vanmo still supports.
- Share a SwiftUI view only when both apps need the same platform-neutral behavior.

### Icons

- Do not use emoji as icons.
- Use SF Symbols or an asset named by the platform Figma frame. Keep one visual weight on a surface.
- Keep icon point sizes consistent within a control row.
- Do not add an external SVG when an SF Symbol matches the specified icon.

### Interaction

- Pressed, hover, selected, disabled, and focused states are visible.
- Hover and press feedback must not reflow neighboring layout.
- Ordinary control motion stays between 150ms and 300ms. Do not use a duration above 500ms for a micro-interaction.
- On iOS, tap is the primary action. Hover is not the only way to reach an action.
- On macOS, pointer style follows the platform frame and existing controls. Use the pointing cursor for text links. Keyboard focus stays visible.

### Color, Light, and Dark

- Use `Color+Vanmo`, `MacDesignTokens`, and system semantic colors. Do not invent a parallel palette from a skill search.
- Body text keeps at least a 4.5:1 contrast ratio in both light and dark appearance. Muted text stays readable; do not use a faint gray for body copy.
- Materials and glass stay opaque enough to read in light mode. Borders stay visible in both appearances.
- Check both appearances before delivery. Do not encode status by color alone.

### Layout and Spacing

- Take spacing, radius, and type from the Figma frame or the existing screen rhythm. Do not introduce one-off padding for a single control.
- Respect safe areas, toolbars, sidebars, and player chrome. Content must not sit under fixed bars.
- Check iOS compact width and the relevant regular width. Check a practical macOS window size. Do not leave an unintended horizontal scroll.

### Motion and Screen States

- A network-backed, persisted, or long-running screen covers empty, loading, success, error, and retry, as required by [`../FRONTEND.md`](../FRONTEND.md).
- Honor Reduce Motion. Non-essential animation is skipped and the settled state is shown immediately.
- A view uses one or two meaningful motions. Continuous animation is reserved for progress.
- Prefer opacity and transform. Do not animate layout size for decoration.

### SwiftUI

These rules match the skill's `swiftui` stack and the repository Swift conventions:

- Views are structs. Keep `body` small and move orchestration to the existing view model or store.
- View-local values use `@State`. Shared observable state has one owner.
- Long collections use lazy stacks and stable identifiers.
- View-scoped async work uses `.task` so disappearance cancels it.
- A changed reusable or screen-level view has a preview for its representative states.

### Accessibility

- Icon-only controls have an accessibility label, and a value, hint, or trait when the control needs one.
- Dynamic Type does not clip an essential label or control.
- Focus order follows the reading order. Keyboard focus is visible on macOS.
- Touch targets stay comfortable on iOS. Pointer targets stay usable on macOS.

## Pre-Delivery Checklist

- [ ] The `ui-ux-pro-max` design-system search was run, and its result did not override Figma or existing tokens.
- [ ] The correct iOS or macOS Figma frame was matched, or the missing frame was designed first.
- [ ] Icons are SF Symbols or approved assets, with no emoji icons and no mixed weights.
- [ ] Press, hover, selected, disabled, and focus states are visible and do not shift layout.
- [ ] Light and dark text, materials, and borders remain readable.
- [ ] Empty, loading, success, error, and retry are present where the screen requires them.
- [ ] Reduce Motion, Dynamic Type, and accessibility labels were considered.
- [ ] Spacing and type follow the frame or the existing screen rhythm.

## Out of Scope for the Skill

- Do not implement with Tailwind, React, Heroicons, Lucide, or Google Fonts.
- Do not replace Vanmo colors or SF Symbols with a generated web design system.
- Do not treat a search recommendation as implemented behavior.
