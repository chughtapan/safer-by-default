/**
 * @file Per-rule PRINCIPLES.md anchors. URLs pin to `main` so the
 * anchor resolves against the current heading text; the slug follows
 * GitHub's heading-to-anchor algorithm (lowercase, spaces and dots
 * to hyphens, drop other non-alphanumeric).
 */

import type { ArchitectureRuleId } from "../analyzer/rule-ids.js";

const PRINCIPLES_BASE =
  "https://github.com/chughtapan/safer-by-default/blob/main/PRINCIPLES.md";

// PRINCIPLES.md heading anchors, named so each rule maps to the doctrine it
// enforces and the slug appears once.
const DISCIPLINE_OVER_CAPABILITY = "#5-discipline-over-capability";
const VALIDATE_AT_BOUNDARY = "#2-validate-at-every-boundary--schemas-where-data-enters-types-inside";
const THE_BUDGET_GATE = "#6-the-budget-gate--scope-is-a-hard-budget";
const THE_RATCHET = "#8-the-ratchet--escalate-up-not-around";

/** PRINCIPLES.md anchor for each architecture rule. */
const ARCHITECTURE_RULE_ANCHORS: Readonly<Record<ArchitectureRuleId, string>> = {
  "no-inventory-barrel": DISCIPLINE_OVER_CAPABILITY,
  "no-internal-subpath-export": DISCIPLINE_OVER_CAPABILITY,
  "no-public-vendor-type-leak": VALIDATE_AT_BOUNDARY,
  "no-export-star-boundary": DISCIPLINE_OVER_CAPABILITY,
  "no-folder-cycle": THE_RATCHET,
  "no-root-internal-cycle": THE_RATCHET,
  "no-large-public-surface": THE_BUDGET_GATE,
  "no-cross-domain-sibling-import": THE_RATCHET,
  "no-upward-layer-import": THE_RATCHET,
  "no-public-test-helper-leak": DISCIPLINE_OVER_CAPABILITY,
  "no-implementation-file-public-entry": DISCIPLINE_OVER_CAPABILITY,
  "no-public-infra-type-leak": VALIDATE_AT_BOUNDARY,
  "no-package-mesh": THE_RATCHET,
  "no-large-folder": THE_BUDGET_GATE,
  "folder-readme-required": DISCIPLINE_OVER_CAPABILITY,
  "no-distant-folder-import": THE_RATCHET,
  "require-curated-public-facade": DISCIPLINE_OVER_CAPABILITY,
  "require-boundary-owned-types": VALIDATE_AT_BOUNDARY,
  "folder-explicit-api-required": THE_BUDGET_GATE,
  "file-implicit-boundary-module": THE_BUDGET_GATE,
  "shared-kernel-cohesion": DISCIPLINE_OVER_CAPABILITY,
  "no-trivial-sink-file": DISCIPLINE_OVER_CAPABILITY,
  "no-fat-orchestrator": DISCIPLINE_OVER_CAPABILITY,
  "architecture-directive-parse-error": DISCIPLINE_OVER_CAPABILITY,
};

const FALLBACK_CODE_DESCRIPTION: { readonly href: string } = Object.freeze({
  href: PRINCIPLES_BASE,
});

/** Pre-built frozen `codeDescription` per rule id. */
const ARCHITECTURE_RULE_CODE_DESCRIPTIONS: Readonly<
  Record<ArchitectureRuleId, { readonly href: string }>
> = Object.freeze(
  Object.fromEntries(
    Object.entries(ARCHITECTURE_RULE_ANCHORS).map(([id, anchor]) => [
      id,
      Object.freeze({ href: `${PRINCIPLES_BASE}${anchor}` }),
    ]),
  ) as Record<ArchitectureRuleId, { readonly href: string }>,
);

/**
 * `codeDescription` for `ruleId`. Returns a shared frozen object. Unknown rule
 * ids fall back to the PRINCIPLES.md root. The parameter is `string` because the
 * analyzer's `ArchitectureDiagnostic.ruleId` is `string`; exhaustiveness is
 * enforced by `ARCHITECTURE_RULE_ANCHORS`' `Record<ArchitectureRuleId, …>` type,
 * which fails compilation if a rule id added to `rule-ids.ts` is missing an anchor.
 */
export function ruleCodeDescription(
  ruleId: string,
): { readonly href: string } {
  return (
    ARCHITECTURE_RULE_CODE_DESCRIPTIONS[ruleId as ArchitectureRuleId] ??
    FALLBACK_CODE_DESCRIPTION
  );
}
