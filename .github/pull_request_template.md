## What and why

<!-- What does this change, and why? Link the issue it addresses. -->

## Checklist

- [ ] `swift test -c release` passes
- [ ] New or changed behaviour has a test that fails without the change
- [ ] No tolerance was loosened to make a reference comparison pass (a difference from exSpy or HyperSpy is a bug unless marked `DEVIATION` with a reason)
- [ ] Docs updated, including `docs/parity.md` if the supported features changed
- [ ] Results that report `validation: "none"` are not described as validated
