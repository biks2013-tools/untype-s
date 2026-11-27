import { anthropicMessagesApi } from "@earendil-works/pi-ai/api/anthropic-messages.lazy";
import { createProvider } from "@earendil-works/pi-ai/models";
import { ANTHROPIC_MODELS } from "@earendil-works/pi-ai/providers/anthropic.models";

/**
 * Claude on Azure AI Foundry, as the provider `azure-anthropic` (pi-ai 1.5.2 has no such provider: its
 * `anthropic` one always calls api.anthropic.com).
 *
 * The same variables as untype's own Refine / Translate (`ConfigResolver`, provider azure-anthropic):
 *   ANTHROPIC_FOUNDRY_API_KEY   the Foundry resource key, sent as `x-api-key`
 *   ANTHROPIC_FOUNDRY_RESOURCE  the resource name: https://<resource>.services.ai.azure.com/anthropic
 *   ANTHROPIC_FOUNDRY_BASE_URL  or the whole address (only one of the two; none has a default)
 * The models are the Claude models of pi-ai's catalog; on Foundry a model is called by its deployment
 * name, which untype expects to be the model id (as the deployments are named: claude-opus-5-5, …).
 */
export const AZURE_ANTHROPIC_PROVIDER = "azure-anthropic";

type Env = (name: string) => string | undefined | Promise<string | undefined>;

/**
 * The Foundry address the Anthropic SDK is given (it appends `/v1/messages` itself). Throws when neither
 * or both of the address settings are set.
 */
export async function foundryBaseUrl(env: Env): Promise<string> {
  const baseUrl = (await env("ANTHROPIC_FOUNDRY_BASE_URL"))?.trim() || undefined;
  const resource = (await env("ANTHROPIC_FOUNDRY_RESOURCE"))?.trim() || undefined;
  if (baseUrl && resource) throw new Error("Set only one of ANTHROPIC_FOUNDRY_RESOURCE and ANTHROPIC_FOUNDRY_BASE_URL.");
  if (!baseUrl && !resource) {
    throw new Error("Claude on Azure Foundry needs ANTHROPIC_FOUNDRY_RESOURCE (or ANTHROPIC_FOUNDRY_BASE_URL).");
  }
  const raw = baseUrl ?? `https://${resource}.services.ai.azure.com/anthropic`;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new Error(`ANTHROPIC_FOUNDRY_BASE_URL is not an address: ${raw}`);
  }
  // An address copied with the endpoint's path (…/anthropic/v1/messages) is cut back to …/anthropic.
  url.pathname = url.pathname.replace(/\/+$/, "").replace(/\/v1(\/messages)?$/, "");
  url.search = "";
  return url.toString().replace(/\/+$/, "");
}

export function azureAnthropicProvider() {
  return createProvider({
    id: AZURE_ANTHROPIC_PROVIDER,
    name: "Claude on Azure Foundry",
    auth: {
      apiKey: {
        name: "Azure Foundry resource key",
        resolve: async ({ ctx, signal }) => {
          signal.throwIfAborted();
          const apiKey = (await ctx.env("ANTHROPIC_FOUNDRY_API_KEY"))?.trim();
          if (!apiKey) return undefined;
          // Per request: the provider's address replaces the catalog's api.anthropic.com.
          const baseUrl = await foundryBaseUrl((name) => ctx.env(name));
          return { auth: { apiKey, baseUrl }, source: "ANTHROPIC_FOUNDRY_API_KEY" };
        },
      },
    },
    models: Object.values(ANTHROPIC_MODELS).map((model) => ({ ...model, provider: AZURE_ANTHROPIC_PROVIDER, baseUrl: "" })),
    api: anthropicMessagesApi(),
  });
}
