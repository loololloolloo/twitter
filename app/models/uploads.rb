# Stores uploaded images and avatars on disk under public/uploads.
#
# Only the extension is taken from the client-supplied filename; the stored
# name is generated here, so a hostile filename cannot escape the upload
# directory or shadow another file.
module Uploads
  ROOT = Rails.root.join("public", "uploads")
  ALLOWED_IMAGE_EXT = %w[.png .jpg .jpeg .gif .webp].freeze

  def self.store(file, user_id, scope: "media")
    return nil if file.blank? || !file.respond_to?(:original_filename)

    original = file.original_filename.to_s
    return nil if original.blank?

    ext = File.extname(original).downcase
    return nil unless ALLOWED_IMAGE_EXT.include?(ext)

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