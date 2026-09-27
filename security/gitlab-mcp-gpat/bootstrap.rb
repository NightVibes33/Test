# frozen_string_literal: true
ApplicationSetting.current.update!(mcp_server_enabled: true)

root = User.find_by_username!("root")
root.personal_access_tokens.where(name: "h1-mcp-bootstrap").find_each(&:revoke!)
token = root.personal_access_tokens.create!(
  name: "h1-mcp-bootstrap",
  scopes: ["api"],
  expires_at: Date.current + 1.day
)
puts "H1_ROOT_TOKEN=#{token.token}"
