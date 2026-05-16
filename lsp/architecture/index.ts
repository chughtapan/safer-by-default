/**
 * @file Public entry for the architecture LSP package.
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
