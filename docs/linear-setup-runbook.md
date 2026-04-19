# Linear Setup Runbook for safer-by-default

Automate Linear workspace setup for SBD team, labels, projects, and cycles.

## Prerequisites

Ensure you have:
- `curl` and `jq` installed
- Write access to linear.app/moltzap workspace
- Write access to chughtapan organization on GitHub

## Step 1: Generate Linear API Key

1. Go to https://linear.app/moltzap/settings/api
2. Under "Personal API keys", click "Create key"
3. Name: `safer-by-default-setup`
4. Copy the key (begins with `lin_`); you'll use it in Step 3

## Step 2: Install Linear GitHub App

1. Go to https://linear.app/moltzap/settings/integrations
2. Find "GitHub" integration; click "Connect"
3. Authorize the Linear app on the chughtapan organization
4. Set sync mode to **reference-only** (no auto-import from GitHub)

## Step 3: Export and Run

Export your API key and run the setup script:

```bash
export LINEAR_API_KEY="<your-api-key-from-step-1>"
./bin/safer-linear-setup
```

Expected output: `STATUS: OK — team SBD ready, 11 labels created/verified, 6 projects created/verified, cycles enabled`

## Step 4: Verify

The script is idempotent — safe to re-run. To verify both sides are linked:

```bash
# Create a test issue in Linear referencing GitHub
# Open any open sbd GitHub issue and comment with a Linear ID (e.g., SBD-1)
# Within 60 seconds, the reference should appear in both systems
```

Done! Your Linear workspace is ready for safer-by-default work.
