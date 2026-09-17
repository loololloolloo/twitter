# Temporary accounts for browser-driven verification of the settings features.
# Safe to delete afterwards; they are ordinary members, not bots.
require "securerandom"

PASSWORD = "password123"

%w[repro_alpha repro_beta].each do |name|
  user = User.find_by(username: name)
  unless user
    user = User.create!(
      username: name,
      display_name: name.split("_").map(&:capitalize).join(" "),
      email: "#{name}@example.com",
      password_hash: PasswordDigest.hash(PASSWORD),
      role: Role.find_by!(name: "user")
    )
  end
  user.update!(password_hash: PasswordDigest.hash(PASSWORD), theme: "light")
  puts "#{user.id} #{user.username}"
end

# A DM thread between them so "delete my messages" has something to act on.
alpha = User.find_by!(username: "repro_alpha")
beta = User.find_by!(username: "repro_beta")
conversation = DmConversation.between(alpha, beta)
unless conversation.dm_messages.exists?(sender_id: alpha.id)
  conversation.dm_messages.create!(sender: alpha, body: "alpha message to delete")
  conversation.dm_messages.create!(sender: beta, body: "beta message to keep")
end
puts "conversation=#{conversation.id} messages=#{conversation.dm_messages.count}"
puts "alpha_sent=#{DmMessage.where(sender_id: alpha.id).count}"