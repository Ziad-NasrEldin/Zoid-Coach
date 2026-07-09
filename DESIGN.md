---
name: Zoid Coach Sumi-Ink Command System
description: A quiet white-paper command room for daily behavioral coaching on macOS.
colors:
  sumi-ink: "#0D0A0A"
  sumi-paper: "#FFFFFF"
  sumi-soft-paper: "#FAFAFA"
  sumi-mist: "#F5F5F5"
  sumi-rule: "#E0E0E0"
  sumi-pale-rule: "#EDEDED"
  sumi-muted: "#545554"
  sumi-wash: "#F7F5F4"
  sumi-seal: "#C23A2E"
  sumi-seal-deep: "#8F211A"
  sumi-seal-wash: "#F5E5E3"
  sumi-okay: "#2F3A2F"
  danger-field: "#FFECEC"
typography:
  display:
    fontFamily: "Times New Roman, Baskerville, Georgia, serif"
    fontSize: "46px"
    fontWeight: 400
    lineHeight: 0.92
    letterSpacing: "-0.04em"
  headline:
    fontFamily: "Times New Roman, Baskerville, Georgia, serif"
    fontSize: "28px"
    fontWeight: 400
    lineHeight: 1.05
    letterSpacing: "-0.025em"
  body:
    fontFamily: "Hiragino Mincho ProN, Yu Mincho, Times New Roman, Georgia, serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.58
    letterSpacing: "0.025em"
  label:
    fontFamily: "Times New Roman, Baskerville, Georgia, serif"
    fontSize: "10px"
    fontWeight: 400
    lineHeight: 1.2
    letterSpacing: "0.14em"
rounded:
  none: "0px"
  identity: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "10px"
  lg: "14px"
  xl: "18px"
  xxl: "24px"
components:
  button-primary:
    backgroundColor: "{colors.sumi-ink}"
    textColor: "{colors.sumi-paper}"
    typography: "{typography.label}"
    rounded: "{rounded.none}"
    padding: "0 14px"
    height: "44px"
  button-primary-hover:
    backgroundColor: "{colors.sumi-seal}"
    textColor: "{colors.sumi-paper}"
    typography: "{typography.label}"
    rounded: "{rounded.none}"
    padding: "0 14px"
    height: "44px"
  button-quiet:
    backgroundColor: "{colors.sumi-paper}"
    textColor: "{colors.sumi-ink}"
    typography: "{typography.label}"
    rounded: "{rounded.none}"
    padding: "5px 9px"
    height: "28px"
  field-neutral:
    backgroundColor: "{colors.sumi-paper}"
    textColor: "{colors.sumi-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.none}"
    padding: "10px"
  status-attention:
    backgroundColor: "{colors.sumi-seal}"
    textColor: "{colors.sumi-paper}"
    typography: "{typography.label}"
    rounded: "{rounded.none}"
    padding: "4px 7px"
---

# Design System: Zoid Coach Sumi-Ink Command System

## Overview

**Creative North Star: "The Private Command Ledger"**

Zoid Coach uses the canonical Sumi-Ink visual language to make behavioral state feel authored, calm, and operationally truthful.

White paper surfaces carry the workspace.

Black ink defines architecture and primary action.

Pale rules create hierarchy without decorative containers.

Red seal marks attention, commitment, blocked state, and approval.

The interface rejects generic SaaS cards, blue architecture, gradients, glass effects, warm gold, and novelty AI styling.

**Key Characteristics:**

- White paper first.
- Black ink for structure and primary action.
- Red seal as the only saturated product accent.
- Serif English and Japanese typography.
- Ruled rows and boxed command surfaces.
- Zero radius by default.
- Written state labels beside every important color.

## Colors

The palette behaves like ink, paper, quiet graphite rules, and one restrained seal.

### Primary

- **Sumi Ink** (`#0D0A0A`): Primary text, strong structure, selected rows, and primary actions.
- **Sumi Seal** (`#C23A2E`): Attention, active coaching, focus, blocked state, and approval.

### Secondary

- **Sumi Seal Deep** (`#8F211A`): Destructive depth and severe blocked state.
- **Sumi Okay** (`#2F3A2F`): Ready and healthy state with a written label.

### Neutral

- **Sumi Paper** (`#FFFFFF`): Main window, panels, fields, and command surfaces.
- **Sumi Soft Paper** (`#FAFAFA`): Selected or secondary operational surface.
- **Sumi Mist** (`#F5F5F5`): Loading, empty, and quiet stage fields.
- **Sumi Pale Rule** (`#EDEDED`): Default dividers and row boundaries.
- **Sumi Rule** (`#E0E0E0`): Stronger frames and section boundaries.
- **Sumi Muted** (`#545554`): Metadata and secondary copy.
- **Sumi Seal Wash** (`#F5E5E3`): Light attention background with written state.

**The One Seal Rule.** Red seal is the only saturated accent and should remain rare enough to signal a decision.

## Typography

**Display Font:** Times New Roman with Baskerville and Georgia fallbacks.

**Body Font:** Hiragino Mincho ProN and Yu Mincho with Times New Roman and Georgia fallbacks.

**Character:** Editorial serif typography makes the interface feel like a deliberate command ledger rather than a generic dashboard.

### Hierarchy

- **Display** (400, 46px, 0.92): Page title and main daily objective only.
- **Headline** (400, 28px, 1.05): Major sections and decisive empty states.
- **Title** (400, 18px, 1.2): Task title and operational group heading.
- **Body** (400, 14px, 1.58): Explanations and coaching copy, capped near 70 characters per line.
- **Label** (400, 10px, 0.14em): Uppercase metadata, navigation, status, and controls.

**The Operational Type Rule.** Display typography is reserved for daily purpose, while labels and body copy carry the work.

## Elevation

The system is flat by default.

Depth comes from white, soft paper, mist, pale rules, and ink frames instead of drop shadows.

Hover and focus use border and seal changes rather than lifted cards.

**The Flat Ledger Rule.** Surfaces remain flat and ruled, with no decorative shadow stacks.

## Components

### Buttons

- **Shape:** Square with zero radius.
- **Primary:** Sumi ink fill, paper text, uppercase label, 44px height.
- **Hover:** Seal fill with paper text.
- **Focus:** Ink outline with a visible seal underline or adjacent written state.
- **Quiet:** Paper fill, ink text, and pale rule border.
- **Disabled:** Mist fill, muted text, and no opacity-only treatment.

### Chips

- **Style:** Square written labels with one-pixel borders.
- **Selected:** Ink fill with paper text.
- **Attention:** Seal fill with paper text.

### Cards / Containers

- **Corner Style:** Zero radius.
- **Background:** Paper, soft paper, or mist.
- **Shadow Strategy:** No shadows.
- **Border:** One-pixel pale or strong rule.
- **Internal Padding:** 14px to 24px based on information density.

Prefer ruled rows, rails, and ledger sections over repeated cards.

### Inputs / Fields

- **Style:** Paper background, one-pixel strong rule, and zero radius.
- **Focus:** Ink border and seal focus marker.
- **Error:** Danger field background with seal-deep text and a written error.
- **Disabled:** Mist background and muted text.

### Navigation

Navigation uses uppercase serif labels, quiet paper backgrounds, and written selected state.

The current section may use ink inversion or a seal marker.

### Health Ledger

The Release 0 signature component is a ruled health ledger showing source name, state, last activity, evidence, and one repair action.

Healthy, warning, unavailable, and waiting states always include written labels.

## Do's and Don'ts

### Do:

- **Do** place the active task and next action before analytics.
- **Do** use `#0D0A0A` ink for primary structure and `#C23A2E` seal for attention.
- **Do** use one-pixel pale rules for most separation.
- **Do** make missing data visually different from zero.
- **Do** show health and classification confidence in written language.
- **Do** provide keyboard, VoiceOver, reduced-motion, and large-text support.
- **Do** keep interaction motion between 150ms and 250ms and use it only for state feedback.

### Don't:

- **Don't** use blue architecture, blue selected states, decorative gradients, glassmorphism, warm gold, neon accents, or novelty AI styling.
- **Don't** use generic identical card grids when ruled rows or a ledger communicate the relationship better.
- **Don't** use side-stripe accents wider than one pixel.
- **Don't** use rounded controls except for identity imagery.
- **Don't** use color without a written state label.
- **Don't** show an opaque focus score or fabricated precision.
- **Don't** use shame, guilt, disappointment, or moral labels in coaching copy.
