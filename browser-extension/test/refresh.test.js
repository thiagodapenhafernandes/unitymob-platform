import test from "node:test";
import assert from "node:assert/strict";
import { shouldReloadContext } from "../src/context.js";
test("refresh preserves an edit in the same conversation", () => {
  assert.equal(shouldReloadContext(false, true, true), false);
  assert.equal(shouldReloadContext(false, false, true), false);
  assert.equal(shouldReloadContext(false, true, false), true);
});
test("changing conversations invalidates the recipient even while editing", () => {
  assert.equal(shouldReloadContext(true, false, true), true);
  assert.equal(shouldReloadContext(true, true, true), true);
});
