require 'spec_helper'

RSpec.describe Store do
  around { |ex| with_temp_data_root { ex.run } }

  it 'slugifies names and de-dupes against taken slugs' do
    expect(Store.slugify('Acme Consulting, LLC')).to eq('acme-consulting-llc')
    expect(Store.slugify('  Wiz__Bang  ')).to eq('wiz-bang')
    dup = Store.slugify('Acme', taken: ['acme'])
    expect(dup).to match(/\Aacme-\d{1,3}\z/)
  end

  it 'writes and reads JSON atomically with symbol keys' do
    path = File.join(Store.data_root, 'a', 'b', 'x.json')
    Store.write_json(path, { name: 'X', n: 1 })
    expect(File.exist?(path)).to be true
    expect(Store.read_json(path)).to eq(name: 'X', n: 1)
    expect(Store.read_json(File.join(Store.data_root, 'missing.json'))).to be_nil
  end

  it 'lists directory and file names, empty when absent' do
    FileUtils.mkdir_p(File.join(Store.data_root, 'biz', 'clients', 'a'))
    FileUtils.mkdir_p(File.join(Store.data_root, 'biz', 'clients', 'b'))
    Store.write_json(File.join(Store.data_root, 'biz', 'x.json'), {})
    expect(Store.list_dirs(File.join(Store.data_root, 'biz', 'clients'))).to eq(%w[a b])
    expect(Store.list_files(File.join(Store.data_root, 'biz'), '.json')).to eq(['x.json'])
    expect(Store.list_dirs(File.join(Store.data_root, 'nope'))).to eq([])
  end
end
