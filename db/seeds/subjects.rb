# frozen_string_literal: true

# Sample vendor data for testing subject type functionality
# This seed file can be run manually via Rails console or as part of test setup

puts 'Creating sample vendors...'

vendors = [
  {
    subject_type: 'Vendor',
    subject_id: 'V1',
    name: 'Acme Corporation',
    email: 'contact@acmecorp.com',
    phone: '555-0101',
    location:'Building A',
    status: 'Active'
  },
  {
    subject_type: 'Vendor',
    subject_id: 'V2',
    name: 'Widget Industries LLC',
    email: 'info@widgetind.com',
    phone: '555-0102',
    location:'Building B',
    status: 'Active'
  },
  {
    subject_type: 'Vendor',
    subject_id: 'V3',
    name: 'Tech Solutions Inc',
    email: 'sales@techsolutions.com',
    phone: '555-0103',
    uid: 'techsol',
    location:'Remote',
    status: 'Active'
  },
  {
    subject_type: 'Vendor',
    subject_id: 'V4',
    name: 'Global Services Group',
    email: 'hello@globalservices.com',
    phone: '555-0104',
    location:'Building C',
    status: 'Inactive'
  },
  {
    subject_type: 'Vendor',
    subject_id: 'V5',
    name: 'Enterprise Systems Co',
    email: 'contact@entsys.com',
    phone: '555-0105',
    uid: 'entsys',
    location:'Building A',
    status: 'Active'
  },
  {
    subject_type: 'Vendor',
    subject_id: 'V6',
    name: 'Premier Consulting',
    email: 'info@premierconsult.com',
    phone: '555-0106',
    location:'Building D',
    status: 'Active'
  },
  {
    subject_type: 'Vendor',
    subject_id: 'V7',
    name: 'DataTech Partners',
    email: 'contact@datatechpartners.com',
    phone: '555-0107',
    location:'Building B',
    status: 'Inactive'
  },
  {
    subject_type: 'Vendor',
    subject_id: 'V8',
    name: 'Cloud Services Ltd',
    email: 'support@cloudservices.com',
    phone: '555-0108',
    uid: 'cloudserv',
    location:'Remote',
    status: 'Active'
  }
]

vendors.each do |vendor_attrs|
  vendor = Subject.find_or_create_by(
    subject_type: vendor_attrs[:subject_type],
    subject_id: vendor_attrs[:subject_id]
  ) do |v|
    v.assign_attributes(vendor_attrs)
  end

  if vendor.persisted?
    puts "  ✓ Created vendor: #{vendor.name} (#{vendor.subject_id})"
  else
    puts "  ✗ Failed to create vendor: #{vendor_attrs[:name]} - #{vendor.errors.full_messages.join(', ')}"
  end
end

puts "Finished! Created #{Subject.vendors.count} vendors (#{Subject.active.count} active, #{Subject.inactive.count} inactive)"
