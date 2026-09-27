# GitLab fine-grained PAT cross-boundary PoC

Target: GitLab EE 19.4.1, tested locally only.

Hypothesis:

A fine-grained personal access token scoped only to source project **A** with the permission needed by `IssueMove` can move an issue from A into target project **B**, even though the token has no granular scope for B.

The user behind the token deliberately has normal Developer access to both A and B. This isolates the fine-grained-token boundary: the account may access both projects, but the token is supposed to be confined to A.

The workflow performs three differential tests:

1. A legacy API PAT moves an owned test issue **B -> A** to prove the account's ambient permissions allow the operation.
2. The A-only fine-grained PAT attempts **B -> A** and must be rejected because B is outside its scope.
3. The same A-only fine-grained PAT attempts **A -> B**. If this succeeds, the target boundary was not enforced for the token.

All objects are created inside the ephemeral local GitLab container. No gitlab.com customer data or third-party projects are touched.
