# Peer channel (MoltZap roster dispatch)

Read this only when dispatched inside a MoltZap-capable AO session, signalled by `AO_SESSION`, `MOLTZAP_LOCAL_SENDER_ID`, and `AO_CALLER_TYPE` all being set. With no such env, skip peer emission entirely and let the orchestrator reconcile from GitHub.

`safer-peer-message` is the only transport primitive a skill uses for peer coordination (SPEC r4.1 §5(d)). Reaching past it into the MoltZap or MCP SDKs, or into the host's bridge and transport modules, is out of bounds for skill bodies. Peer messages point at durable artifacts via `--artifact-url` and never carry the artifact body (Invariant 8): publish the design doc, spec, PR, or review verdict to GitHub first, then send the pointer.

Typical use, publishing an artifact URL back to the orchestrator once the artifact lands. Substitute your own modality for `<modality>` in the `--from` argument:

```bash
PEER_OUT=$(printf '%s' "$BODY" | safer-peer-message \
  --to-role orchestrator \
  --kind artifact-published \
  --artifact-url "$ARTIFACT_URL" \
  --correlation-id "$SESSION-1" \
  --body-stdin) || case $? in
    10) echo "$PEER_OUT" >&2 ;;   # ReroutedToOrchestrator (recipient retired)
    21) safer-escalate --from <modality> --to orchestrate --cause recipient-retired ;;
    20|22) safer-escalate --from <modality> --to orchestrate --cause peer-transport-invalid ;;
    30|*) safer-escalate --from <modality> --to orchestrate --cause peer-transport-failed ;;
  esac
```

Exit codes other than the ones handled above are transport failures; route them through `safer-escalate` rather than retrying inline.
