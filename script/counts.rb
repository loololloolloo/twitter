bots = User.where(is_bot: true)
puts "bots=#{bots.count}"
puts "avatar not_null=#{bots.where.not(avatar_path: nil).count}"
puts "avatar non_empty=#{bots.where.not(avatar_path: [nil, ""]).count}"
puts "avatar empty_str=#{bots.where(avatar_path: "").count}"
puts "avatar null=#{bots.where(avatar_path: nil).count}"
puts "banner non_empty=#{bots.where.not(banner_path: [nil, ""]).count}"
puts "banner null=#{bots.where(banner_path: nil).count}"