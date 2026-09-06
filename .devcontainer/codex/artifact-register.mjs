import { registerHooks } from "node:module";
import { pathToFileURL } from "node:url";
const runtimeParent = pathToFileURL("/opt/codex-artifacts/node/runtime-entry.mjs").href;
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith(".") || specifier.startsWith("/") || /^[a-z]+:/.test(specifier)) {
      return nextResolve(specifier, context);
    }
    try {
      return nextResolve(specifier, { ...context, parentURL: runtimeParent });
    } catch (error) {
      if (error.code !== "ERR_MODULE_NOT_FOUND") throw error;
      return nextResolve(specifier, context);
    }
  },
});
