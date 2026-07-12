require 'spec_helper'

RSpec.describe Store::Business do
  around { |ex| with_temp_data_root { ex.run } }

  let(:attrs) do
    { name: 'Acme Consulting, LLC', contact: 'Me', email: 'a@x.com',
      street: '1 Main', city: 'Charlotte', state: 'NC', zip: '28203' }
  end

  it 'creates a business dir with settings.json and default period monthly' do
    b = Store::Business.create(attrs)
    expect(b.slug).to eq('acme-consulting-llc')
    expect(File.exist?(File.join(Store.data_root, 'acme-consulting-llc', 'config', 'settings.json'))).to be true
    expect(b.defaults[:timesheet_period]).to eq('monthly')
    expect(b.city_state_zip).to eq('Charlotte, NC 28203')
  end

  it 'lists and finds businesses, de-duping slugs' do
    Store::Business.create(attrs)
    b2 = Store::Business.create(attrs.merge(name: 'Acme Consulting, LLC'))
    expect(b2.slug).to match(/\Aacme-consulting-llc-\d/)
    expect(Store::Business.all.map(&:slug)).to include('acme-consulting-llc', b2.slug)
    expect(Store::Business.find('acme-consulting-llc').name).to eq('Acme Consulting, LLC')
    expect(Store::Business.find('nope')).to be_nil
  end

  it 'updates fields without moving the directory and saves a logo' do
    b = Store::Business.create(attrs)
    b.update(contact: 'New Contact', defaults: { timesheet_period: 'weekly' })
    expect(Store::Business.find(b.slug).contact).to eq('New Contact')
    expect(Store::Business.find(b.slug).defaults[:timesheet_period]).to eq('weekly')

    src = File.join(Store.data_root, 'src.png')
    File.write(src, 'PNGDATA')
    b.save_logo(src)
    expect(b.logo_file).to eq(File.join(b.dir, 'config', 'logo.png'))
    expect(b.resolve_logo[:web]).to match(%r{\A/businesses/logo\?v=\d+\z})
  end

  it 'reserves the "new" and "logo" slugs so a business cannot shadow those routes' do
    expect(Store::Business.create(attrs.merge(name: 'New')).slug).not_to eq('new')
    expect(Store::Business.create(attrs.merge(name: 'Logo')).slug).not_to eq('logo')
  end
end
