# frozen_string_literal: true

Feature.enable(:granular_personal_access_tokens)

root = User.find_by_username!("root")
root.personal_access_tokens.where(name: "h1-bootstrap").find_each(&:revoke!)

token = root.personal_access_tokens.create!(
  name: "h1-bootstrap",
  scopes: ["api"],
  expires_at: Date.current + 1.day
)

puts "H1_ROOT_TOKEN=#{token.token}"
