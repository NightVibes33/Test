# frozen_string_literal: true

user_id = Integer(ENV.fetch("H1_USER_ID"))
source_project_id = Integer(ENV.fetch("H1_SOURCE_PROJECT_ID"))
target_project_id = Integer(ENV.fetch("H1_TARGET_PROJECT_ID"))

user = User.find(user_id)
source = Project.find(source_project_id)
target = Project.find(target_project_id)

Feature.enable(:granular_personal_access_tokens)
Feature.enable(:granular_personal_access_tokens, user)

# Replace any earlier harness token so reruns stay deterministic.
user.personal_access_tokens.where(name: "h1-source-only-gpat").find_each(&:revoke!)

create = PersonalAccessTokens::CreateService.new(
  current_user: user,
  target_user: user,
  organization_id: user.organization_id,
  params: {
    name: "h1-source-only-gpat",
    scopes: ["granular"],
    granular: true,
    expires_at: Date.current + 1.day
  }
).execute

abort("GPAT_CREATE_ERROR=#{create.message}") if create.error?

token = create.payload.fetch(:personal_access_token)
assignable = Authz::PermissionGroups::Assignable.for_permission(:move_issue).first
abort("NO_ASSIGNABLE_FOR_MOVE_ISSUE") unless assignable

source_boundary = Authz::Boundary.for(source)
target_boundary = Authz::Boundary.for(target)

scope = Authz::GranularScope.new(
  namespace: source_boundary.namespace,
  access: source_boundary.access,
  permissions: [assignable.name]
)

scope_result = Authz::GranularScopeService.new(token).add_granular_scopes(scope)
abort("GPAT_SCOPE_ERROR=#{scope_result.message}") if scope_result.error?

token.reload

puts "H1_GPAT=#{token.token}"
puts "H1_ASSIGNABLE=#{assignable.name}"
puts "H1_SOURCE_PROJECT_ID=#{source.id}"
puts "H1_SOURCE_NAMESPACE_ID=#{source_boundary.namespace&.id}"
puts "H1_TARGET_PROJECT_ID=#{target.id}"
puts "H1_TARGET_NAMESPACE_ID=#{target_boundary.namespace&.id}"
puts "H1_SCOPE_ROWS=#{token.granular_scopes.map { |s| [s.access, s.namespace_id, s.permissions] }.inspect}"
