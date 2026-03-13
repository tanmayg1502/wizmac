# Wizmac Docs

This folder is the durable technical map for the project. Use the smallest document that answers your question.

## Start With

- [architecture.md](architecture.md): system shape, runtime boundaries, trust model, and persistence
- [implementation-guide.md](implementation-guide.md): where to change things and how to extend features safely

## Surface Area

- [control-plane.md](control-plane.md): CLI, JSON-RPC, MCP, service methods, transports, and source/origin semantics
- [operations.md](operations.md): lifecycle, permissions, data files, remote pairing, and troubleshooting
- [testing.md](testing.md): test suites, fixture workflows, and benchmark guidance

## Recommended Reading Order

### For humans new to the repo

1. `../README.md`
2. `architecture.md`
3. `implementation-guide.md`
4. `testing.md`

### For agents making code changes

1. `../AGENTS.md`
2. `implementation-guide.md`
3. `control-plane.md` or `testing.md`, depending on the task

### For operators using the CLI or service

1. `control-plane.md`
2. `operations.md`
