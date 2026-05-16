/**
 * @file Top-level barrel for the architecture LSP package. Exposes
 * the analyzer entry (`analyzeWorkspace`) for non-LSP callers (CI
 * shim, tests) and re-exports the diagnostic types so consumers
 * can type-check against the analyzer's output without reaching
 * into nested paths.
 */

export { analyzeWorkspace } from "./analyzer/index.js";
export type {
  ArchitectureDiagnostic,
  ArchitectureDiagnosticRuleId,
  ArchitectureOptionsInput,
  ArchitectureReport,
  ArchitectureSeverity,
  ResolvedArchitectureOptions,
} from "./analyzer/project/api/index.js";
export {
  ARCHITECTURE_DIAGNOSTIC_RULE_IDS,
  ARCHITECTURE_DIRECTIVE_PARSE_ERROR_RULE_ID,
  type ArchitectureRuleId,
} from "./analyzer/rule-ids.js";
