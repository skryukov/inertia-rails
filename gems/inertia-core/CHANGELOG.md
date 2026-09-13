# Changelog

All notable changes to `inertia-core` are documented in this file. The gem is
released in lockstep with [`inertia_rails`](../../CHANGELOG.md), which carries
the full notes for each version.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

* First release: the framework-agnostic half of the Inertia.js server protocol, extracted from `inertia_rails`. Prop types and their resolution against a visit, the page object and its metadata, the response a render answers with (JSON or first load, SSR with fallback, head tags), the protocol decisions every adapter shares (asset version, redirect rewrites, location responses), a Rack middleware and request, an SSR client, a configuration with an `option` DSL, a resolution observer, live props, precognition, the XSRF cookie policy, and DevTools recording (the entry format, the prop badges, redaction, ULIDs and the file-backed store). Plain Ruby: `require 'inertia/core'` loads without Rails or ActiveSupport. The adapter contract is in [README.md](README.md) (@skryukov)
