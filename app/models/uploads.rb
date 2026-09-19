# Stores uploaded images and avatars on disk under public/uploads.
#
# Only the extension is taken from the client-supplied filename; the stored
# name is generated here, so a hostile filename cannot escape the upload
# directory or shadow another file.
module Uploads
  ROOT = Rails.root.join("public", "uploads")
  ALLOWED_IMAGE_EXT = %w[.png .jpg .jpeg .gif .webp].freeze

  # 2019 shipped native video in the composer. The set is deliberately small:
  # these are the containers a browser can play directly, so a stored video
  # never needs transcoding to be viewable.
  ALLOWED_VIDEO_EXT = %w[.mp4 .m4v .mov .webm].freeze

  ALLOWED_EXT = (ALLOWED_IMAGE_EXT + ALLOWED_VIDEO_EXT).freeze

  # Whether a stored path is a video, decided from its extension rather than
  # from the upload's content type: the stored name is generated here, so the
  # extension is the one trusted piece of metadata on disk.
  def self.video?(relative)
    relative.present? && ALLOWED_VIDEO_EXT.include?(File.extname(relative.to_s).downcase)
  end

  # The MIME type for a stored path, from the same extension map. The <source>
  # element uses it so the browser does not have to guess a container, which it
  # cannot do reliably for a file it has only just been handed.
  CONTENT_TYPES = {
    ".mp4" => "video/mp4", ".m4v" => "video/mp4", ".mov" => "video/quicktime",
    ".webm" => "video/webm", ".png" => "image/png", ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg", ".gif" => "image/gif", ".webp" => "image/webp"
  }.freeze

  def self.content_type(relative)
    CONTENT_TYPES[File.extname(relative.to_s).downcase] || "application/octet-stream"
  end

  def self.store(file, user_id, scope: "media")
    return nil if file.blank? || !file.respond_to?(:original_filename)

    original = file.original_filename.to_s
    return nil if original.blank?

    ext = File.extname(original).downcase
    return nil unless ALLOWED_EXT.include?(ext)

    relative = "#{scope}/#{user_id}_#{SecureRandom.hex(8)}#{ext}"
    destination = ROOT.join(relative)
    FileUtils.mkdir_p(destination.dirname)

    # A File object from a test or a temp file is copied straight across;
    # a Rack upload is streamed.
    if file.respond_to?(:tempfile)
      FileUtils.cp(file.tempfile.path, destination)
    else
      IO.copy_stream(file, destination.to_s)
    end

    relative
  end

  # Deletes a previously stored file. Used when a picture is replaced, so the
  # old one does not linger on disk forever; a bulk import would otherwise
  # leave one orphan per account it touched.
  #
  # The path is checked to be inside ROOT before anything is removed, so a
  # value that arrived from the database cannot be used to delete an arbitrary
  # file elsewhere on the filesystem.
  def self.remove(relative)
    return if relative.blank?

    path = ROOT.join(relative.to_s).cleanpath
    return unless path.to_s.start_with?(ROOT.to_s + File::SEPARATOR)
    return unless File.file?(path)

    File.delete(path)
  rescue SystemCallError
    nil
  end
end