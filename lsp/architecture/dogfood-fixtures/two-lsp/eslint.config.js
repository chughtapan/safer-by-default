import tsParser from "@typescript-eslint/parser";
import acg from "eslint-plugin-agent-code-guard";

export default [
  {
    files: ["src/**/*.ts"],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: 2022,
        sourceType: "module",
      },
    },
    plugins: {
      "agent-code-guard": acg,
    },
    rules: {
      "agent-code-guard/record-cast": "error",
    },
  },
];
