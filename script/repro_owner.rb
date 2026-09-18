require "securerandom"

PASSWORD = "password123!"

owner = User.order(:id).first
puts "owner=#{owner.username} id=#{owner.id} sent_before=#{DmMessage.where(sender_id: owner.id).count}"

owner.update!(password_hash: PasswordDigest.hash(PASSWORD))
other = User.where.not(id: owner.id).first
conversation = DmConversation.between(owner, other)
conversation.dm_messages.create!(sender: owner, body: "owner message meant to be cleared")
puts "owner_sent_after=#{DmMessage.where(sender_id: owner.id).count} conv=#{conversation.id}"