# frozen_string_literal: true
user = User.find(Integer(ENV.fetch("H1_USER_ID")))

Feature.enable(:granular_personal_access_tokens)
Feature.enable(:granular_personal_access_tokens, user)
ApplicationSetting.current.update!(mcp_server_enabled: true)

user.personal_access_tokens.where(name: "h1-mcp-only-gpat").find_each(&:revoke!)

result = PersonalAccessTokens::CreateService.new(
  current_user: user,
  target_user: user,
  organization_id: user.organization_id,
  params: {
    name: "h1-mcp-only-gpat",
    scopes: ["granular"],
    granular: true,
    expires_at: Date.current + 1.day
  }
).execute

abort("CREATE_ERROR=#{result.message}") if result.error?
pat = result.payload.fetch(:personal_access_token)

assignable = Authz::PermissionGroups::Assignable.for_permission(:execute_mcp_tool).first
abort("NO_EXECUTE_MCP_ASSIGNABLE") unless assignable

scope = Authz::GranularScope.new(
  namespace: nil,
  access: Authz::GranularScope::Access::USER,
  permissions: [assignable.name]
)

scope_result = Authz::GranularScopeService.new(pat).add_granular_scopes(scope)
abort("SCOPE_ERROR=#{scope_result.message}") if scope_result.error?

pat.reload
puts "H1_GPAT=#{pat.token}"
puts "H1_SCOPE=#{pat.granular_scopes.map { |s| [s.access, s.namespace_id, s.permissions] }.inspect}"
