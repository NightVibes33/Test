# GitLab MCP granular PAT authorization bypass PoC

Target: GitLab EE 19.4.1, local-only reproduction.

Hypothesis: GitLab intentionally allows granular PATs to authenticate to the MCP endpoint using
the user-level `execute_mcp_tool` permission. GraphQL-backed MCP services discard the access token
and execute GraphQL with only `current_user`. GitLab's GraphQL granular authorization returns
success when `context[:access_token]` is absent.

Differential proof:

1. Create a private project B and a user who legitimately has Developer access to B.
2. Create a granular PAT containing only `execute_mcp_tool` at the user boundary—no project scopes.
3. Query B directly through GraphQL with that PAT. Expected: denied/null because the token lacks
   `read_project` for B.
4. Use the same PAT on `/api/v4/mcp` and call `get_project` for B.
5. If MCP returns B, the granular PAT's resource/permission confinement has been dropped and the
   token inherits the account owner's ambient permissions.

No gitlab.com customer data is touched.
