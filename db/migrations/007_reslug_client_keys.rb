Sequel.migration do
  up do
    seen = {}
    from(:clients).each do |client|
      slug = client[:name].to_s.downcase.gsub(/[^\w\s-]/, '').gsub(/[\s_]+/, '-').gsub(/-+/, '-').gsub(/\A-|-\z/, '')
      slug = "#{slug}-#{rand(100)}" while seen[slug] || from(:clients).exclude(id: client[:id]).first(client_key: slug)
      seen[slug] = true
      from(:clients).where(id: client[:id]).update(client_key: slug)
    end
  end

  down do
    # Irreversible — original acronym keys are not recoverable
  end
end
