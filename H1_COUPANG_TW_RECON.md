# Coupang Taiwan HackerOne recon — 2026-09-28

Program: coupang_tw
Program status: open / paid
Program start: 2026-03-16
Researcher reports on this program: 0
Publicly disclosed reports returned by HackerOne during setup: 0
Maximum severity on listed primary web/mobile assets: Critical

## Why this target
- Not represented by an existing H1 branch in NightVibes33/Test.
- Newer open paid program after excluded/rejected candidates.
- Current policy does not prohibit AI-assisted research.
- Large set of explicit Critical-cap assets.
- Several Critical assets were added in March 2026, including cart/cash/checkout/payment/member/API/mobile surfaces.
- Coupang notes Taiwan/Korea can share backend code, so duplicate avoidance must include cross-region/fix-equivalence concerns.

## Initial low-noise priority
Prefer self-contained, explicitly scoped surfaces that can produce high-impact authorization or upload flaws without touching other users:
1. fileupload.tw.coupang.com
2. fileupload-video.tw.coupang.com
3. cart-front-api.tw.coupang.com
4. id.tw.coupang.com
5. rs-open-api.tw.coupang.com
6. checkout.tw.coupang.com / payment.tw.coupang.com only with strict non-transactional testing

## Candidate classes
- Broken object/function-level authorization
- Authentication/session boundary failures
- File upload validation leading to server-side impact
- SSRF through upload/import/fetch-style functionality
- Server-side injection/RCE only when safely demonstrable
- Cross-region authorization/fix mismatch only if live impact differs from known/shared behavior

## Duplicate controls
- Compare against our HackerOne private report history before submission.
- Compare against public HackerOne disclosures.
- Search NightVibes33/Test branches before starting a new hypothesis.
- Search public GitHub references for prior research/artifacts.
- Remember: other researchers' private/undisclosed HackerOne submissions are not visible to us.

## Rules
- Use only owned accounts/data.
- Keep traffic low-volume.
- No destructive actions, DoS, or privacy-invasive testing.
- Stop at minimum evidence necessary to establish impact.
