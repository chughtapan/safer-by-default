// Fixture file carrying BOTH violations the two-LSP dogfood asserts:
//   * Syntax (eslint): `(await r.json()) as Record<string, unknown>` trips
//     `agent-code-guard/record-cast`.
//   * Architecture: importing across sibling domains (`auth -> billing`)
//     trips `no-cross-domain-sibling-import`.

import type { Invoice } from "../billing/invoice.js";

type WithInvoice = { readonly invoice?: Invoice };

export async function loadUser(r: Response): Promise<WithInvoice> {
  const body = (await r.json()) as Record<string, unknown>;
  return body as WithInvoice;
}
