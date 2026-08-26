# Model-Friendly References

This directory contains compact, model-friendly summaries of Vanmo-specific
facts that are expensive to rediscover during routine work.

## Authority Boundary

References are navigation and recall aids. They do not override:

1. current code and tests
2. `project.yml` and `Packages/VanmoCore/Package.swift`
3. `ARCHITECTURE.md`
4. official Apple, XcodeGen, package, or service documentation

When a reference conflicts with a higher-authority source, follow the
higher-authority source and refresh the reference in the same change.

## Available References

- [`design-system-reference-llms.txt`](./design-system-reference-llms.txt):
  verified design-source, platform, token, component, and asset lookup paths
- [`xcodegen-build-reference-llms.txt`](./xcodegen-build-reference-llms.txt):
  project generation, build entry points, and configuration differences

## Refresh Responsibility

The person or agent changing an upstream design convention, component location,
target definition, build command, entitlement, or compilation condition is
responsible for refreshing the affected reference in the same change. Check the
listed source paths before editing, keep summaries concise, and do not copy
large external documents into this directory.

Generated or mechanically derived material belongs in
[`../generated/`](../generated/), not here.
