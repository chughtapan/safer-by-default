#!/usr/bin/env bun
// THROWAWAY SPIKE CODE — /safer:spike modality. Not production.
// Craft principles 1-4 suspended. Do not ship.
//
// Demux probe for sbd#107: spawn N synthetic moltzap-like conversations
// through one Channels plugin, inject numbered probes, check whether Claude
// attributes each `reply(chat_id, ...)` call to the right chat_id and echoes
// the right probe token.
//
// Run:
//   claude --dangerously-load-development-channels server:demux-probe
//   (with .mcp.json: "demux-probe": { "command": "bun", "args": ["./probe.ts"] })
//
// Tune N, RATE_MS, ROUNDS below. Restart Claude Code between N-values.

import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { ListToolsRequestSchema, CallToolRequestSchema } from '@modelcontextprotocol/sdk/types.js'

const N = Number(process.env.PROBE_N ?? 4)          // concurrent conversations
const RATE_MS = Number(process.env.PROBE_RATE_MS ?? 2000)  // ms between events
const ROUNDS = Number(process.env.PROBE_ROUNDS ?? 10)  // events per conversation

type Observation = {
  replied_chat_id: string
  reply_text: string
  matched_token: string | null   // the probe-X-Y token found in reply_text, if any
  ts: number
}
const observations: Observation[] = []
let issuedSeq = 0

const mcp = new Server(
  { name: 'demux-probe', version: '0.0.1' },
  {
    capabilities: {
      experimental: { 'claude/channel': {} },
      tools: {},
    },
    instructions:
      'Each <channel source="demux-probe" chat_id="..."> event contains a probe token ' +
      'of the form probe-<chat_id>-<seq>. Reply via the reply tool, passing the chat_id ' +
      'from the inbound tag and INCLUDING the probe token verbatim in your reply text so ' +
      'attribution can be verified. Keep replies terse; one sentence is fine.',
  },
)

mcp.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: 'reply',
    description: 'Send a message back on a given chat_id. Include the probe token.',
    inputSchema: {
      type: 'object',
      properties: {
        chat_id: { type: 'string' },
        text: { type: 'string' },
      },
      required: ['chat_id', 'text'],
    },
  }],
}))

const PROBE_RE = /probe-(\d+)-(\d+)/

mcp.setRequestHandler(CallToolRequestSchema, async req => {
  if (req.params.name !== 'reply') throw new Error(`unknown tool: ${req.params.name}`)
  const { chat_id, text } = req.params.arguments as { chat_id: string; text: string }
  const m = PROBE_RE.exec(text)
  observations.push({
    replied_chat_id: chat_id,
    reply_text: text.slice(0, 200),
    matched_token: m ? `probe-${m[1]}-${m[2]}` : null,
    ts: Date.now(),
  })
  // Attribution check: did Claude echo a token whose chat_id matches the
  // chat_id it replied on?
  const expected_cid = m ? m[1] : null
  const ok = expected_cid !== null && expected_cid === chat_id
  process.stderr.write(
    `[probe] reply chat_id=${chat_id} token=${m ? m[0] : 'NONE'} ok=${ok}\n`,
  )
  return { content: [{ type: 'text', text: 'sent' }] }
})

await mcp.connect(new StdioServerTransport())

// Event loop: round-robin across N chat_ids, ROUNDS events per chat.
;(async () => {
  for (let round = 1; round <= ROUNDS; round++) {
    for (let c = 1; c <= N; c++) {
      const seq = ++issuedSeq
      const token = `probe-${c}-${seq}`
      await mcp.notification({
        method: 'notifications/claude/channel',
        params: {
          content: `Echo this token back on your reply: ${token}. Keep the reply short.`,
          meta: { chat_id: String(c), probe_seq: String(seq) },
        },
      })
      process.stderr.write(`[probe] emit chat_id=${c} token=${token}\n`)
      await new Promise(r => setTimeout(r, RATE_MS))
    }
  }
  // Give Claude a moment to catch up, then dump results.
  await new Promise(r => setTimeout(r, 10_000))
  const correct = observations.filter(o => {
    if (!o.matched_token) return false
    const m = PROBE_RE.exec(o.matched_token)!
    return m[1] === o.replied_chat_id
  }).length
  process.stderr.write(
    `\n[probe] RESULT N=${N} ROUNDS=${ROUNDS} observations=${observations.length} ` +
    `correct=${correct} error_rate=${(1 - correct / observations.length).toFixed(3)}\n`,
  )
})()
