/**
 * @file Per-rule PRINCIPLES.md anchors. Each architecture rule
 * projects from one or two principles; the diagnostic-converter
 * surfaces this as `codeDescription.href` so the editor's "Learn
 * more" UI links to the canonical doctrine entry.
 *
 * URLs pin to `main` so anchors auto-resolve as PRINCIPLES.md
 * evolves. The anchor slugs follow GitHub's heading-to-anchor
 * algorithm: lowercase, spaces and dots become hyphens, all other
 * non-alphanumeric characters are stripped. Verified against the
 * current PRINCIPLES.md headings.
 */

import type { ArchitectureRuleId } from "../analyzer/rule-ids.js";

const PRINCIPLES_BASE =
  "https://github.com/chughtapan/safer-by-default/blob/main/PRINCIPLES.md";

// PRINCIPLES.md heading anchors. Names match the principle numbers
// 1-8 plus auxiliary sections used by the architecture taxonomy.
const ANCHOR_VALIDATE_BOUNDARY = "#2-validate-at-every-boundary--schemas-where-data-enters-types-inside";
const ANCHOR_DISCIPLINE = "#5-discipline-over-capability";
const ANCHOR_BUDGET_GATE = "#6-the-budget-gate--scope-is-a-hard-budget";
const ANCHOR_RATCHET = "#8-the-ratchet--escalate-up-not-around";

/**
 * Map every architecture rule id to the PRINCIPLES.md anchor that
 * names the doctrine it enforces. Architecture rules are mostly
 * projections of the discipline section (Principles 5-8) plus the
 * boundary-validation principle (2) for vendor-type leak rules.
 *
 * The directive-parse pseudo-rule points at the discipline anchor
 * because malformed directives are a discipline failure (an unanchored
 * suppression bypassing the architecture contract).
 */
const ARCHITECTURE_RULE_ANCHORS: Readonly<Record<ArchitectureRuleId, string>> = {
  "no-inventory-barrel": ANCHOR_DISCIPLINE,
  "no-internal-subpath-export": ANCHOR_DISCIPLINE,
  "no-public-vendor-type-leak": ANCHOR_VALIDATE_BOUNDARY,
  "no-export-star-boundary": ANCHOR_DISCIPLINE,
  "no-folder-cycle": ANCHOR_RATCHET,
  "no-root-internal-cycle": ANCHOR_RATCHET,
  "no-large-public-surface": ANCHOR_BUDGET_GATE,
  "no-cross-domain-sibling-import": ANCHOR_RATCHET,
  "no-upward-layer-import": ANCHOR_RATCHET,
  "no-public-test-helper-leak": ANCHOR_DISCIPLINE,
  "no-implementation-file-public-entry": ANCHOR_DISCIPLINE,
  "no-public-infra-type-leak": ANCHOR_VALIDATE_BOUNDARY,
  "no-package-mesh": ANCHOR_RATCHET,
  "no-large-folder": ANCHOR_BUDGET_GATE,
  "folder-readme-required": ANCHOR_DISCIPLINE,
  "no-distant-folder-import": ANCHOR_RATCHET,
  "require-curated-public-facade": ANCHOR_DISCIPLINE,
  "require-boundary-owned-types": ANCHOR_VALIDATE_BOUNDARY,
  "folder-explicit-api-required": ANCHOR_BUDGET_GATE,
  "file-implicit-boundary-module": ANCHOR_BUDGET_GATE,
  "shared-kernel-cohesion": ANCHOR_DISCIPLINE,
  "no-trivial-sink-file": ANCHOR_DISCIPLINE,
  "no-fat-orchestrator": ANCHOR_DISCIPLINE,
  "architecture-directive-parse-error": ANCHOR_DISCIPLINE,
};

/**
 * Build the PRINCIPLES.md URL for the doctrine entry a given
 * architecture rule enforces. Unknown rule ids fall back to the
 * PRINCIPLES.md root — every architecture finding carries an
 * actionable link.
 */
export function ruleDocUrl(ruleId: string): string {
  const anchor = ARCHITECTURE_RULE_ANCHORS[ruleId as ArchitectureRuleId];
  if (anchor === undefined) return PRINCIPLES_BASE;
  return `${PRINCIPLES_BASE}${anchor}`;
}
