#!/bin/sh
# Upstream rc.2's HMR loader requires Node's internal ESM loader. The native
# fallback does not recognize the official Node 22.23 build, so pass the
# upstream-documented command-line workaround explicitly (NODE_OPTIONS rejects
# this flag). Keep this wrapper until DeepSeek Harness removes that dependency.
exec node --expose-internals \
  /opt/deepseek-harness/node_modules/@deepseek-ai/dsh/lib/bin.js "$@"
