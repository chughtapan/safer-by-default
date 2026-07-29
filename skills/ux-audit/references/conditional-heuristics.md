# Conditional heuristics (H5, H6)

Run H5 when the surface has forms; run H6 when a ticket export or issue thread is attached to the invocation.

## H5 — Form & microinteraction

For every form in scope, `/browse` exercises three input states:

1. **Empty submission.** Does the form prevent submit, show errors, focus the first invalid field?
2. **Invalid input** (wrong type, malformed email, out-of-range number). Does the form catch on blur or only on submit? Are error messages specific to the field?
3. **Valid submission.** Does the success state acknowledge submission, redirect cleanly, prevent double-submit?

For every form, record:

| Field | Type | Label placement | Required marked | Validation timing | Error message specificity | Autocomplete attribute |
|---|---|---|---|---|---|---|

Column definitions:

- **Field.** Input `name` attribute or visible label.
- **Type.** Value of the HTML `type` attribute (`text`, `email`, `password`, `number`, `tel`, etc.).
- **Label placement.** One of `top`, `inline`, `placeholder-only` (anti-pattern), `floating`, `none` (anti-pattern).
- **Required marked.** `yes`, `no`, or `implicit` (only revealed on validation error).
- **Validation timing.** `on-blur`, `on-submit`, `on-input`, or `none`.
- **Error message specificity.** `field-specific` (names what's wrong), `generic` ("invalid input"), or `none`.
- **Autocomplete attribute.** Record the literal value (`email`, `current-password`, `cc-number`, etc.); flag `off` or absent on fields that should accept autofill per the WHATWG autocomplete tokens.

Microinteraction findings cover hover, focus, transitions, optimistic updates, double-click guards, empty states. Cite each finding by selector or screenshot.

No `/qa`. Same iron-rule reason as H2. `/qa-only` is allowed for the structured reporting shape.

## H6 — Stakeholder & artifact read

Read what the team has already said:

```bash
ls docs/ design/ 2>/dev/null
[ -f DESIGN.md ]    && echo "DESIGN.md exists; read it"
[ -f docs/PRD.md ]  && echo "PRD exists; read it"

gh issue list --label "ux,design,ux-bug,usability" --state all --limit 30
gh pr list --search "<scope keyword>" --state all --limit 30
```

If the user attached a support-ticket export (CSV / JSON / pasted snippet), read it and extract complaint themes by frequency. Do not invent ticket data; if no export is attached, note "no ticket data attached" in the writeup and continue. H6 ticket attachments are optional. Missing them does not block the audit.

H6 output is one paragraph: "Team intended X. Recent complaints say Y. Z was tried (commit / PR ref). Open threads: A, B." This paragraph informs Phase 4's Relevance section.

Optional one-shot composition: `/plan-ceo-review` to stress-test the named goal before the rest of the audit runs. Off by default; user opts in via `--challenge-goal`. Runs hold-scope autonomous; escalate to `/safer:orchestrate` if it would prompt the user.

