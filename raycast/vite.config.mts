import format from "ultracite/oxfmt";
import antiSlop from "ultracite/oxlint/anti-slop";
import core from "ultracite/oxlint/core";
import react from "ultracite/oxlint/react";
import { defineConfig } from "vite-plus";

const ignorePatterns = [".raycast-build-*/**"];

export default defineConfig({
  fmt: {
    ...format,
    ignorePatterns: [...format.ignorePatterns, ...ignorePatterns],
    sortPackageJson: false,
  },
  lint: {
    extends: [core, react, antiSlop],
    ignorePatterns: [...core.ignorePatterns, ...ignorePatterns],
    jsPlugins: [
      { name: "@tanstack/query", specifier: "@tanstack/eslint-plugin-query" },
      { name: "@raycast", specifier: "@raycast/eslint-plugin" },
    ],
    plugins: ["eslint", "typescript", "unicorn", "oxc", "import", "react"],
    rules: {
      "eslint/class-methods-use-this": "off",
      "eslint/complexity": "off",
      "eslint/func-style": ["error", "declaration"],
      "eslint/no-empty-function": "off",
      "eslint/no-negated-condition": "off",
      "eslint/no-nested-ternary": "off",
      "eslint/no-use-before-define": "off",
      "eslint/no-void": "off",
      "eslint/sort-keys": "off",
      "react/function-component-definition": [
        "error",
        {
          namedComponents: "function-declaration",
          unnamedComponents: "arrow-function",
        },
      ],
      "typescript/parameter-properties": "off",
      "unicorn/no-negated-condition": "off",
      "unicorn/prefer-ternary": "off",
      "@raycast/no-ambiguous-platform-shortcut": "warn",
      "@raycast/no-reserved-shortcut": "warn",
      "@raycast/prefer-common-shortcut": "warn",
      "@raycast/prefer-ellipsis": "warn",
      "@raycast/prefer-title-case": "warn",
      "@tanstack/query/exhaustive-deps": "error",
      "@tanstack/query/infinite-query-property-order": "error",
      "@tanstack/query/mutation-property-order": "error",
      "@tanstack/query/no-rest-destructuring": "warn",
      "@tanstack/query/no-unstable-deps": "error",
      "@tanstack/query/no-void-query-fn": "error",
      "@tanstack/query/stable-query-client": "error",
      "oxc/no-accumulating-spread": "error",
    },
  },
});
