#!/usr/bin/env python3
"""test_checkout_invalid_tier expects 400, but CheckoutRequest.tier is now
Literal["pro","enterprise"], so an invalid tier is rejected by Pydantic with 422 (fail-fast,
correct FastAPI behavior) before the handler's 400 path. Update the stale assertion to 422.
This red test has been blocking all of test-automation-agent's merges to develop."""
p = "backend/tests/test_billing.py"
s = open(p).read()
old = ('        "/api/billing/checkout", json={"tier": "starter"}, headers={"Authorization": f"Bearer {token}"}\n'
       '    )\n'
       '    assert r.status_code == 400\n')
new = ('        "/api/billing/checkout", json={"tier": "starter"}, headers={"Authorization": f"Bearer {token}"}\n'
       '    )\n'
       '    # CheckoutRequest.tier is Literal["pro","enterprise"] -> Pydantic rejects an invalid\n'
       '    # tier with 422 (fail-fast) before the handler\'s 400 path.\n'
       '    assert r.status_code == 422\n')
assert s.count(old) == 1, f"anchor count={s.count(old)}"
open(p, "w").write(s.replace(old, new, 1))
print("fixed test_checkout_invalid_tier: 400 -> 422")
