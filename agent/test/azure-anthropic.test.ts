import assert from "node:assert/strict";
import { test } from "node:test";
import { builtinModels } from "@earendil-works/pi-ai/providers/all";
import { AZURE_ANTHROPIC_PROVIDER, azureAnthropicProvider, foundryBaseUrl } from "../src/azure-anthropic.js";

const env = (values: Record<string, string>) => (name: string) => values[name];

test("the Foundry address comes from the resource name", async () => {
  assert.equal(await foundryBaseUrl(env({ ANTHROPIC_FOUNDRY_RESOURCE: "my-res" })), "https://my-res.services.ai.azure.com/anthropic");
});

test("a whole address is kept, without the endpoint's /v1/messages", async () => {
  for (const given of [
    "https://x.services.ai.azure.com/anthropic",
    "https://x.services.ai.azure.com/anthropic/",
    "https://x.services.ai.azure.com/anthropic/v1",
    "https://x.services.ai.azure.com/anthropic/v1/messages",
  ]) {
    assert.equal(await foundryBaseUrl(env({ ANTHROPIC_FOUNDRY_BASE_URL: given })), "https://x.services.ai.azure.com/anthropic");
  }
});

test("neither or both address settings is an error, never a default", async () => {
  await assert.rejects(foundryBaseUrl(env({})), /ANTHROPIC_FOUNDRY_RESOURCE/);
  await assert.rejects(
    foundryBaseUrl(env({ ANTHROPIC_FOUNDRY_RESOURCE: "a", ANTHROPIC_FOUNDRY_BASE_URL: "https://a.services.ai.azure.com/anthropic" })),
    /only one/,
  );
  await assert.rejects(foundryBaseUrl(env({ ANTHROPIC_FOUNDRY_BASE_URL: "not a url" })), /not an address/);
});

test("the provider lists the Claude models under its own id", () => {
  const models = builtinModels();
  models.setProvider(azureAnthropicProvider());
  const model = models.getModel(AZURE_ANTHROPIC_PROVIDER, "claude-opus-5-5");
  assert.ok(model);
  assert.equal(model.provider, AZURE_ANTHROPIC_PROVIDER);
  assert.equal(model.api, "anthropic-messages");
  // pi-ai's own anthropic provider is untouched.
  assert.equal(models.getModel("anthropic", "claude-opus-5-5")?.provider, "anthropic");
});
