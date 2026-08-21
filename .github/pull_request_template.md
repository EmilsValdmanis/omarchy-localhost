## Summary

<!-- What changed, and why. Link the issue if there is one. -->

## Testing

<!-- Note anything CI will not catch, such as Omarchy-specific checks. -->

- [ ] `node --test tests/*.mjs`
- [ ] `python3 -m unittest discover -s tests -p 'test_*.py'`
- [ ] `omarchy plugin validate .` and `qmllint`, when available

## Checklist

- [ ] Change stays focused, and user-visible behavior is documented.
- [ ] Tests cover behavior changes where practical.
- [ ] No secrets, private addresses, or unrelated generated files.
