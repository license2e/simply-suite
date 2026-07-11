module Store
  module_function

  def slugify(name, taken: [])
    base = name.to_s.downcase
              .gsub(/[^\w\s-]/, '')
              .gsub(/[\s_]+/, '-')
              .gsub(/-+/, '-')
              .gsub(/\A-|-\z/, '')
    base = 'item' if base.empty?
    slug = base
    slug = "#{base}-#{rand(100)}" while taken.include?(slug)
    slug
  end

  def read_json(path)
    return nil unless File.exist?(path)
    JSON.parse(File.read(path), symbolize_names: true)
  end

  def write_json(path, hash)
    FileUtils.mkdir_p(File.dirname(path))
    tmp = "#{path}.tmp.#{SecureRandom.hex(4)}"
    File.write(tmp, JSON.pretty_generate(hash))
    File.rename(tmp, path)
    path
  end

  def list_dirs(path)
    return [] unless File.directory?(path)
    Dir.children(path).select { |e| File.directory?(File.join(path, e)) }.sort
  end

  def list_files(path, ext)
    return [] unless File.directory?(path)
    Dir.children(path).select { |e| e.end_with?(ext) && File.file?(File.join(path, e)) }.sort
  end

  def now_iso
    Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  end

  def move(src, dest)
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.mv(src, dest)
  end
end
